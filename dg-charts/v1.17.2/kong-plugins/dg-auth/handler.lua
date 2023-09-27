local http = require "socket.http"
local ltn12 = require "ltn12"

local DgAuth = {
    VERSION = "1.0.0",
    PRIORITY = 10
}

local kong = kong

function DgAuth:access(config)
    kong.log("access start")

    local url = kong.request.get_scheme() .. "://" .. kong.request.get_host() .. "/api/Login/KeepAlive"
    local sessionId = kong.request.get_header("x-auth-sessionId")

    if sessionId == nil then
        return kong.response.exit(401, {
            message = "Required x-auth-sessionId header not found"
        })
    end

    local request_body = "{\"UserSessionId\": \"" .. sessionId .. "\"}"
    local response_body = {}

    kong.log("request to " .. url)
    kong.log("with body " .. request_body)

    local r, c, h, s = http.request {
        url = url,
        method = 'POST',
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = string.len(request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }

    kong.log('body:' .. tostring(r))
    kong.log('code:' .. tostring(c))
    kong.log('status:' .. tostring(s))

    if not (c >= 200 and c < 400) then
        return kong.response.exit(401, {
            message = "Invalid authentication credentials"
        })
    end

    -- local credential, err = kong.cache:get(credential_cache_key, nil, load_credential, credential_cache_key)
    -- if err then
    --     kong.log.err(err)
    --     return kong.response.exit(500, {
    --         message = "Unexpected error"
    --     })
    -- end

    -- if not credential then
    --     -- no credentials in cache nor datastore
    --     return kong.response.exit(401, {
    --         message = "Invalid authentication credentials"
    --     })
    -- end

    -- set an upstream header if the credential exists and is valid
    -- kong.service.request.set_header("X-API-Key", credential.apikey)

    kong.log("access end")
end

-- return the created table, so that Kong can execute it
return DgAuth
