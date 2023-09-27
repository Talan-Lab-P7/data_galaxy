local httpc = require("resty.http")

local ltn12 = require "ltn12"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local cjson = require "cjson"

local DgAuth = {
    VERSION = "1.0.0",
    PRIORITY = 10
}

local kong = kong

service = {
    protocol = "http",
    host = "datagalaxyservicesweb",
    port = 80
}

local function getUrl(route)
    return service.protocol .. "://" .. service.host .. ":" .. service.port .. route
end


urls = {
    keepAlive = getUrl("/api/KeepAlive"),
    integrationLogin = getUrl("/api/Login/IntegrationLogin")
}

cacheTtlConstants = {
    accessToken = 10, -- 10 seconds
    integrationToken = 2 * 60 * 60 -- 2 hours
}

local function has_value (tab, val)
    for index, value in ipairs(tab) do
        if string.match(val, value) then
            -- kong.log("string.match(" .. val .. ", " .. value .. ") : true")
            return true
        else
            -- kong.log("string.match(" .. val .. ", " .. value .. ") : false")
        end
    end

    return false
end


local function dumpObject(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dumpObject(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end

 local function getAccessTokenCacheKey(token) 
    return kong.db.accessTokenCacheEntries:cache_key(token) 
end

local function getIntegrationTokenCacheKey(token) 
    return kong.db.integrationTokenCacheEntries:cache_key(token) 
end

local function prepareAuthorizationHeader(token)
    return "Bearer " .. token
end

local function setRequestAuthorizationHeader(authToken) 
    kong.service.request.set_header("Authorization", prepareAuthorizationHeader(authToken))
end

local function tryValidateIntegrationLogin(integrationTokenCacheKey, authToken) 
    kong.log("tryValidateIntegrationLogin: START")

    local request_body = "{ \"Token\": \"" .. authToken .. "\" }"

    local res, err = httpc.new():request_uri(urls.integrationLogin, {
        scheme = kong.request.get_scheme(),
        method = "POST",
        headers = {
            ["Authorization"] = prepareAuthorizationHeader(authToken),
            ["Content-Length"] = string.len(request_body),
            ["Content-Type"] = "application/json"
        },
        body = request_body
    })

    kong.log.inspect(err, res)

    local status = res.status
    local body   = res.body

    if (err or not (status >= 200 and status < 400)) then
        kong.log("integrationLogin failed with integrationToken " .. authToken)
        return nil
    end

    -- Need to decode Json response
    local bodyjson = cjson.decode(body)
    local accessToken = bodyjson["AccessToken"]

    return { cache_key = integrationTokenCacheKey, accessToken = accessToken, integrationToken = authToken }, err
end


--[[

This method is called when there is a cache MISS on the Access Token cache
It will try the KeepAlive method to validate the token
If it fails, it will try the IntegrationLogin method with either integrationValue (containing the integrationToken)
or the received authToken

]]
local function tryValidateAccessToken(authToken, integrationValue) 
    kong.log("3. Access Token Cache Entry not found, need to Refresh using Keep Alive mechanism")
    kong.log("tryValidateAccessToken:START")
    
    local accessToken = authToken
    local accessTokenCacheKey = getAccessTokenCacheKey(authToken)

    kong.log("tryValidateAccessToken:START CacheKey:" .. accessTokenCacheKey )
    kong.log("tryValidateAccessToken:START AuthToken:" .. authToken )

    local res, err = httpc.new():request_uri(urls.keepAlive, {
        scheme = kong.request.get_scheme(),
        method = "GET",
        headers = {
            ["Authorization"] = prepareAuthorizationHeader(authToken),
        },
    })

    
    kong.log.inspect(err, res)
    
    local status = res.status
    local length = res.headers["Content-Length"]
    local body   = res.body

    if not (status >= 200 and status < 400) then
        kong.log("checkKeepAlive:keepAlive call failed with accessToken " .. authToken)

        kong.log("Will try IntegrationLogin...")

        --[[
        This optimization seems dangerous for now: Maybe we'll need to clean the cache entry in the IntegrationTokenCache at some point

        if hasIntegrationTokenCacheHit then
            kong.log("no need to try integrationLogin: already validated")
            return nil
        end
        --]]

        local integrationToken = authToken
        -- If we had a cache HIT on the IntegrationToken cache, the integrationToken is obtained from that cache entry
        if ( not ( integrationValue == nil )) then
            integrationToken = integrationValue.integrationToken
        end 

        local integrationTokenCacheKey =  getIntegrationTokenCacheKey(authToken) 
        local integrationCacheEntry, integrationCacheErr = kong.cache:get(integrationTokenCacheKey, { ttl = cacheTtlConstants.integrationToken }, tryValidateIntegrationLogin, integrationTokenCacheKey, authToken)

        if integrationCacheEntry == nil then
            -- Ensure Cache Entry is evicted from cache
            kong.cache:invalidate(integrationTokenCacheKey)
            return nil
        end

        accessToken = integrationCacheEntry.accessToken
        kong.log("After Integration, AccessToken: " .. accessToken)
    else
        kong.log("checkKeepAlive:KeepAlive SUCCESS")
    end

    local cacheEntry = { cache_key = accessTokenCacheKey, key = accessToken }

    kong.log("checkKeepAlive:Returning Cache Entry.." .. dumpObject(cacheEntry))
    return cacheEntry, err
end

local function probeAccessTokenCache(accessToken)
    local accessTokenCacheKey = getAccessTokenCacheKey(accessToken)
    local ttl, probeErr, probeValue = kong.cache:probe(accessTokenCacheKey)

    -- If we have a cache hit, nothing to do
    if ttl then
        kong.log("END: Access Token Cache Hit: Nothing more to do")
        kong.log.inspect.off()
        return true
    end

    return false
end

function DgAuth:access(config)
    kong.log("DgAuth:access: ==================== REQUEST STARTED ===================")
    kong.log.inspect.on()

    local requestPath = kong.request.get_path()

    -- if OPTIONS request, nothing more to be done
    if ( kong.request.get_method() == "OPTIONS" ) then
        kong.log("request verb is OPTIONS : ", requestPath, " ignored")
        return
    end

    -- if route not included or excluded, nothing more to be done
    local isNotIncluded = not has_value(config.included_routes, requestPath)
    local isExcluded = has_value(config.excluded_routes, requestPath)
    if ( isNotIncluded or isExcluded ) then
        kong.log("access end - Not Included: ", isNotIncluded, ", Excluded: ", isExcluded)
        return
    end


    -- kong.log.inspect("urls.keepAlive: ", urls.keepAlive, "\nurls.integrationLogin", urls.integrationLogin)

    local authHeader = kong.request.get_header("Authorization")
    
    if authHeader == nil then
        return kong.response.exit(401, {
            message = "Required Authorization header not found"
        })
    end

    local authToken = string.gsub(authHeader, "Bearer ", "")

    local jwt, err = jwt_decoder:new(authToken)
    if err then
        return kong.response.exit(401, {
            message = "Bad token; " .. tostring(err)
        })
    end

    -- First: Check for value in cache using probe
    kong.log("1. Checking for Cache Probe success (Access Token Cache)")
    local hasAccessTokenHit = probeAccessTokenCache(authToken)
    if hasAccessTokenHit then
        kong.log("=> SUCCESS: Access Token Cache Hit, end of processing")
        return
    end

    local accessTokenCacheKey = getAccessTokenCacheKey(authToken)
    local integrationTokenCacheKey =  getIntegrationTokenCacheKey(authToken)

    kong.log("2. Checking for Cache Probe success (Integration Token Cache)")
    local integrationTtl, integrationErr, integrationValue = kong.cache:probe(integrationTokenCacheKey)

    -- If we have an IntegrationTokenCache hit, we get the authToken, authHeader from it
    if (integrationTtl and integrationValue) then 
        kong.log("Integration token Cache Hit")
        authToken = integrationValue.accessToken
        authHeader = prepareAuthorizationHeader(authToken)
        accessTokenCacheKey = getAccessTokenCacheKey(authToken)
    end

    kong.log("3. Checking in AccessTokenCache...")
    local cacheEntry, errCache = kong.cache:get(accessTokenCacheKey, { ttl = cacheTtlConstants.accessToken }, tryValidateAccessToken, authToken, integrationvalue)

    if (errCache or cacheEntry == nil) then
        if ( cacheEntry == nil ) then
            -- Ensure Cache Entry is evicted from cache
            kong.cache:invalidate(accessTokenCacheKey)
        end

        local errorMessage
        if errCache then
            errorMessage = dump(errCache)
        else
            errorMessage = "Invalid authentication credentials: " .. authToken
        end

        return kong.response.exit(401, {
            message = errorMessage
        })

    end

    
    kong.log("Cache Success")
    setRequestAuthorizationHeader(cacheEntry.key)

    kong.log("access end")
    kong.log.inspect.off()
end

return DgAuth
