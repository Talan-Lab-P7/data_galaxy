local typedefs = require "kong.db.schema.typedefs"


return {
  name = "dg-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          {
            included_routes = {
              type = "array",
              required = false,
              elements = {
                type = "string"
              },
              default = {
                ".*"
              }
            },
          },
          {
            excluded_routes = {
              type = "array",
              required = false,
              elements = {
                type = "string"
              },
              default = {}
            },
          }
    }, }, },
  },
}