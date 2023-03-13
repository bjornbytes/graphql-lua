local clock = require('clock')
local fiber = require('fiber')
local log = require('log')

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

-- Based on https://github.com/tarantool/crud/blob/5717e87e1f8a6fb852c26181524fafdbc7a472d8/test/helper.lua#L533-L544
function helpers.fflush_main_server_output(server, capture)
    -- Sometimes we have a delay here. This hack helps to wait for the end of
    -- the output. It shouldn't take much time.
    local helper_msg = "metrics fflush message"
    if server then
        server.net_box:eval([[
            require('log').error(...)
        ]], {helper_msg})
    else
        log.error(helper_msg)
    end

    local max_wait_timeout = 10
    local start_time = clock.monotonic()

    local captured = ""
    while (not string.find(captured, helper_msg, 1, true))
    and (clock.monotonic() - start_time < max_wait_timeout) do
        local captured_part = capture:flush()
        captured = captured .. (captured_part.stdout or "") .. (captured_part.stderr or "")
        fiber.yield()
    end
    return captured
end

return helpers
