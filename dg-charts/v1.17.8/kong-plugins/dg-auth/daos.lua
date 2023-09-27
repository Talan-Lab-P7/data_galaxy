
local typedefs = require "kong.db.schema.typedefs"

local accessTokenCacheEntries =
  {
    ttl = true,
    primary_key = { "id" },
    name = "accessTokenCacheEntries",
    endpoint_key = "key",
    cache_key = { "key" },
    workspaceable = true,
    admin_api_name = "accces-token-cache",
    admin_api_nested_name = "accces-token-cache",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { key = { type = "string", required = true, unique = true, auto = true }, }
    },
  }

local integrationTokenCacheEntries =
{
  ttl = true,
  primary_key = { "id" },
  name = "integrationTokenCacheEntries",
  endpoint_key = "key",
  cache_key = { "key" },
  workspaceable = true,
  admin_api_name = "integration-token-cache",
  admin_api_nested_name = "integration-token-cache",
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { key = { type = "string", required = true, unique = true, auto = true }, },
    { accessToken = { type = "string", required = true, unique = true, auto = true }, },
    { integrationToken = { type = "string", required = true, unique = true, auto = true }, },
  },
}

return {
  accessTokenCacheEntries,
  integrationTokenCacheEntries
}