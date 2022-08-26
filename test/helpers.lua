local types = require('graphql.types')
local schema = require('graphql.schema')
local parse = require('graphql.parse')
local validate = require('graphql.validate')
local execute = require('graphql.execute')

local helpers = {}

helpers.test_schema_name = 'default'

function helpers.check_request(query, query_schema, mutation_schema, directives, opts)
    opts = opts or {}
    local root = {
        query = types.object({
            name = 'Query',
            fields = query_schema or {},
        }),
        mutation = types.object({
            name = 'Mutation',
            fields = mutation_schema or {},
        }),
        directives = directives,
    }

    local compiled_schema = schema.create(root, helpers.test_schema_name, opts)

    local parsed = parse.parse(query)

    validate.validate(compiled_schema, parsed)

    local rootValue = {}
    local variables = opts.variables or {}
    return execute.execute(compiled_schema, parsed, rootValue, variables)
end

return helpers
