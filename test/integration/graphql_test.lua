local json = require('json')
local types = require('graphql.types')
local schema = require('graphql.schema')
local parse = require('graphql.parse')
local validate = require('graphql.validate')
local execute = require('graphql.execute')

local t = require('luatest')
local g = t.group('integration')

local function check_request(query, query_schema, opts)
    opts = opts or {}
    local root = {
        query = types.object({
            name = 'Query',
            fields = query_schema,
        }),
        mutation = types.object({
            name = 'Mutation',
            fields = {},
        }),
    }

    local compiled_schema = schema.create(root, 'default')

    local parsed = parse.parse(query)

    validate.validate(compiled_schema, parsed)

    local rootValue = {}
    local variables = opts.variables or {}
    return execute.execute(compiled_schema, parsed, rootValue, variables)
end

function g.test_simple()
     local query = [[
        { test(arg: "A") }
    ]]

    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = types.string.nonNull,
                arg2 = types.string,
                arg3 = types.int,
                arg4 = types.long,
            },
            resolve = callback,
        }
    }

    t.assert_equals(check_request(query, query_schema), {test = 'A'})
end

function g.test_args_order()
    local function callback(_, args)
        local result = ''
        for _, tuple in ipairs(getmetatable(args).__index) do
            result = result .. tuple.value
        end
        return result
    end

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = types.string.nonNull,
                arg2 = types.string,
                arg3 = types.int,
                arg4 = types.long,
            },
            resolve = callback,
        }
    }

    t.assert_equals(check_request([[{ test(arg: "B", arg2: "22") }]], query_schema), {test = 'B22'})
    t.assert_equals(check_request([[{ test(arg2: "22", arg: "B") }]], query_schema), {test = '22B'})
end

function g.test_variables()
    local query = [[
        query ($arg: String! $arg2: String!) { test(arg: $arg, arg2: $arg2) }
    ]]
    local variables = {arg = 'B', arg2 = '22'}

    local function callback(_, args)
        local result = ''
        for _, tuple in ipairs(getmetatable(args).__index) do
            result = result .. tuple.value
        end
        return result
    end

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = types.string.nonNull,
                arg2 = types.string,
                arg3 = types.int,
                arg4 = types.long,
            },
            resolve = callback,
        }
    }

    -- Positive test
    t.assert_equals(check_request(query, query_schema, {variables = variables}), {test = 'B22'})

    -- Negative tests
    local query = [[
        query ($arg: String! $arg2: String!) { test(arg: $arg, arg2: $arg2) }
    ]]

    t.assert_error_msg_equals(
            'Variable "arg2" expected to be non-null',
            function()
                check_request(query, query_schema, {variables = {}})
            end
    )

    local query = [[
        query ($arg: String)
            { test(arg: $arg) }
    ]]
    t.assert_error_msg_equals(
            'Variable "arg" type mismatch:' ..
                    ' the variable type "String" is not compatible' ..
                    ' with the argument type "NonNull(String)"',
            function()
                check_request(query, query_schema, {variables = {}})
            end
    )

    t.assert_error_msg_equals(
            'Required argument "arg" was not supplied.',
            function()
                check_request([[ query { test(arg2: "") } ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Unknown variable "unknown_arg"',
            function()
                check_request([[ query { test(arg: $unknown_arg) } ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'There is no declaration for the variable "unknown_arg"',
            function()
                check_request([[
                    query { test(arg: "") }
                ]], query_schema, { variables = {unknown_arg = ''}})
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "8589934592" to type "Int"',
            function()
                check_request([[
                    query { test(arg: "", arg3: 8589934592) }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "123.4" to type "Int"',
            function()
                check_request([[
                    query { test(arg: "", arg3: 123.4) }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "18446744073709551614" to type "Long"',
            function()
                check_request([[
                    query { test(arg: "", arg4: 18446744073709551614) }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "123.4" to type "Long"',
            function()
                check_request([[
                    query { test(arg: "", arg4: 123.4) }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "inputObject" to type "String"',
            function()
                check_request([[
                    query { test(arg: {a: "123"}, arg4: 123) }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Could not coerce value "list" to type "String"',
            function()
                check_request([[
                    query { test(arg: ["123"], arg4: 123) }
                ]], query_schema)
            end
    )
end

function g.test_error_in_handlers()
    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg=types.string.nonNull,
                arg2=types.string,
                arg3=types.int,
                arg4=types.long,
            },
        }
    }

    query_schema.test.resolve = function()
        error('Error C', 0)
    end

    t.assert_error_msg_equals(
            'Error C',
            function()
                check_request([[
                    { test(arg: "TEST") }
                ]], query_schema)
            end
    )

    query_schema.test.resolve = function()
        return nil, 'Error E'
    end

    t.assert_error_msg_equals(
            'Error E',
            function()
                check_request([[
                    { test(arg: "TEST") }
                ]], query_schema)
            end
    )
end

function g.test_subselections()
    local query_schema = {
        ['test'] = {
            kind = types.object({
                name = 'selection',
                fields = {
                    uri = types.string,
                    uris = types.object({
                        name = 'uris',
                        fields = {
                            uri = types.string,
                        }
                    }),
                }
            }),
            arguments = {
                arg = types.string.nonNull,
            },
        }
    }

    t.assert_error_msg_equals(
            'Scalar field "uri" cannot have subselections',
            function()
                check_request([[
                    { test(arg: "") { uri { id } } }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Composite field "uris" must have subselections',
            function()
                check_request([[
                    { test(arg: "") { uris } }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Field "unknown" is not defined on type "selection"',
            function()
                check_request([[
                    { test(arg: "") { unknown } }
                ]], query_schema)
            end
    )
end

function g.test_enum_input()
    local simple_enum = types.enum({
        name = 'simple_enum',
        values = {
            a = { value = 'a' },
            b = { value = 'b' },
        },
    })
    local input_object = types.inputObject({
        name = 'simple_input_object',
        fields = {
            field = simple_enum,
        }
    })

    local query_schema = {
        ['simple_enum'] = {
            kind = types.string,
            arguments = {
                arg = input_object,
            },
            resolve = function(_, args)
                return args.arg.field
            end
        }
    }

    t.assert_equals(check_request([[
        query($arg: simple_input_object) {
            simple_enum(arg: $arg)
        }
    ]], query_schema, {variables = {arg = {field = 'a'}}}), {simple_enum = 'a'})

    t.assert_error_msg_equals(
            'Wrong variable "arg.field" for the Enum "simple_enum" with value "d"',
            function()
                check_request([[
                    query($arg: simple_input_object) {
                        simple_enum(arg: $arg)
                    }
                ]], query_schema, {variables = {arg = {field = 'd'}}})
            end
    )
end


function g.test_enum_output()
    local simple_enum = types.enum({
        name = 'test_enum_output',
        values = {
            a = { value = 'a' },
            b = { value = 'b' },
        },
    })
    local object = types.object({
        name = 'simple_object',
        fields = {
            value = simple_enum,
        }
    })

    local query_schema = {
        ['test_enum_output'] = {
            kind = object,
            arguments = {},
            resolve = function(_, _)
                return {value = 'a'}
            end
        }
    }

    t.assert_equals(check_request([[
        query {
            test_enum_output{ value }
        }
    ]], query_schema), {test_enum_output = {value = 'a'}})
end

function g.test_unknown_query_mutation()
    t.assert_error_msg_equals(
            'Field "UNKNOWN_TYPE" is not defined on type "Query"',
            function()
                check_request([[
                    query { UNKNOWN_TYPE(arg: "") }
                ]], {})
            end
    )

    t.assert_error_msg_equals(
            'Field "UNKNOWN_TYPE" is not defined on type "Mutation"',
            function()
                check_request([[
                    mutation { UNKNOWN_TYPE(arg: "") }
                ]], {})
            end
    )
end

function g.test_nested_input()
    local nested_InputObject = types.inputObject({
        name = 'nested_InputObject',
        fields = {
            field = types.string.nonNull,
        }
    })

    local query_schema = {
        ['test_nested_InputObject'] = {
            kind = types.string,
            arguments = {
                servers = types.list(nested_InputObject),
            },
            resolve = function(_, args)
                return args.servers[1].field
            end,
        },
        ['test_nested_list'] = {
            kind = types.string,
            arguments = {
                servers = types.list(types.string),
            },
            resolve = function(_, args)
                return args.servers[1]
            end,
        },
        ['test_nested_InputObject_complex'] = {
            kind = types.string,
            arguments = {
                upvalue = types.string,
                servers = types.inputObject({
                    name = 'ComplexInputObject',
                    fields = {
                        field2 = types.string,
                        test = types.inputObject({
                            name = 'ComplexNestedInputObject',
                            fields = {
                                field = types.list(types.string)
                            }
                        }),
                    }
                }),
            },
            resolve = function(_, args)
                return ('%s+%s+%s'):format(args.upvalue, args.servers.field2, args.servers.test.field[1])
            end
        },
    }

    t.assert_equals(check_request([[
        query($field: String!) {
            test_nested_InputObject(
                servers: [{ field: $field }]
            )
        }
    ]], query_schema, {variables = {field = 'echo'}}), {test_nested_InputObject = 'echo'})

    t.assert_error_msg_equals(
            'Unused variable "field"',
            function()
                check_request([[
                    query($field: String!) {
                        test_nested_InputObject(
                            servers: [{ field: "not-variable" }]
                        )
                    }
                ]], query_schema, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($field: String!) {
            test_nested_list(
                servers: [$field]
            )
        }
    ]], query_schema, {variables = {field = 'echo'}}), {test_nested_list = 'echo'})

    t.assert_equals(check_request([[
        query($field: String! $field2: String! $upvalue: String!) {
            test_nested_InputObject_complex(
                upvalue: $upvalue,
                servers: {
                    field2: $field2
                    test: { field: [$field] }
                }
            )
        }
    ]], query_schema, {
        variables = {field = 'echo', field2 = 'field', upvalue = 'upvalue'},
    }), {test_nested_InputObject_complex = 'upvalue+field+echo'})
end

function g.test_custom_type_scalar_variables()
    local function isString(value)
        return type(value) == 'string'
    end

    local function coerceString(value)
        if value ~= nil then
            value = tostring(value)
            if not isString(value) then return end
        end
        return value
    end

    local custom_string = types.scalar({
        name = 'CustomString',
        description = 'Custom string type',
        serialize = coerceString,
        parseValue = coerceString,
        parseLiteral = function(node)
            return coerceString(node.value)
        end,
        isValueOfTheType = isString,
    })

    local function decodeJson(value)
        if value ~= nil then
            return json.decode(value)
        end
        return value
    end

    local json_type = types.scalar({
        name = 'Json',
        description = 'Custom type with JSON decoding',
        serialize = json.encode,
        parseValue = decodeJson,
        parseLiteral = function(node)
            return decodeJson(node.value)
        end,
        isValueOfTheType = isString,
    })

    local query_schema = {
        ['test_custom_type_scalar'] = {
            kind = types.string,
            arguments = {
                field = custom_string.nonNull,
            },
            resolve = function(_, args)
                return args.field
            end,
        },
        ['test_json_type'] = {
            arguments = {
                field = json_type,
            },
            kind = json_type,
            resolve = function(_, args)
                if args.field == nil then
                    return nil
                end
                assert(type(args.field) == 'table', "Field is not a table! ")
                assert(args.field.test ~= nil, "No field 'test' in object!")
                return args.field
            end
        },
        ['test_custom_type_scalar_list'] = {
            kind = types.string,
            arguments = {
                fields = types.list(custom_string.nonNull).nonNull,
            },
            resolve = function(_, args)
                return args.fields[1]
            end
        },
        ['test_custom_type_scalar_inputObject'] = {
            kind = types.string,
            arguments = {
                object = types.inputObject({
                    name = 'ComplexCustomInputObject',
                    fields = {
                        nested_object = types.inputObject({
                            name = 'ComplexCustomNestedInputObject',
                            fields = {
                                field = custom_string,
                            }
                        }),
                    }
                }),
            },
            resolve = function(_, args)
                return args.object.nested_object.field
            end
        }
    }

    t.assert_equals(check_request([[
        query($field: Json) {
            test_json_type(
                field: $field
            )
        }
    ]], query_schema, {
        variables = {field = '{"test": 123}'},
    }), {test_json_type = '{"test":123}'})

    t.assert_equals(check_request([[
        query($field: Json) {
            test_json_type(
                field: $field
            )
        }
    ]], query_schema, {
        variables = {field = box.NULL},
    }), {test_json_type = 'null'})

    t.assert_equals(check_request([[
        query {
            test_json_type(
                field: "null"
            )
        }
    ]], query_schema, {
        variables = {},
    }), {test_json_type = 'null'})

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar(
                field: $field
            )
        }
    ]], query_schema, {
        variables = {field = 'echo'},
    }), {test_custom_type_scalar = 'echo'})

    t.assert_error_msg_equals(
            'Variable "field" type mismatch: ' ..
            'the variable type "NonNull(String)" is not compatible with the argument type '..
            '"NonNull(CustomString)"',
            function()
                check_request([[
                    query($field: String!) {
                        test_custom_type_scalar(
                            field: $field
                        )
                    }
                ]], query_schema, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar_list(
                fields: [$field]
            )
        }
    ]], query_schema, {
        variables = {field = 'echo'},
    }), {test_custom_type_scalar_list = 'echo'})

    t.assert_error_msg_equals(
            'Could not coerce value "inputObject" ' ..
                    'to type "CustomString"',
            function()
                check_request([[
                    query {
                        test_custom_type_scalar_list(
                            fields: [{a: "2"}]
                        )
                    }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Variable "field" type mismatch: ' ..
            'the variable type "NonNull(String)" is not compatible with the argument type '..
            '"NonNull(CustomString)"',
            function()
                check_request([[
                    query($field: String!) {
                        test_custom_type_scalar_list(
                            fields: [$field]
                        )
                    }
                ]], query_schema, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($fields: [CustomString!]!) {
            test_custom_type_scalar_list(
                fields: $fields
            )
        }
    ]], query_schema, {
        variables = {fields = {'echo'}},
    }), {test_custom_type_scalar_list = 'echo'})

    t.assert_error_msg_equals(
            'Variable "fields" type mismatch: ' ..
            'the variable type "NonNull(List(NonNull(String)))" is not compatible with the argument type '..
            '"NonNull(List(NonNull(CustomString)))"',
            function()
                check_request([[
                    query($fields: [String!]!) {
                        test_custom_type_scalar_list(
                            fields: $fields
                        )
                    }
                ]], query_schema, {variables = {fields = {'echo'}}})
            end
    )

    t.assert_error_msg_equals(
            'Variable "fields" type mismatch: ' ..
            'the variable type "List(NonNull(String))" is not compatible with the argument type '..
            '"NonNull(List(NonNull(CustomString)))"',
            function()
                check_request([[
                    query($fields: [String!]) {
                        test_custom_type_scalar_list(
                            fields: $fields
                        )
                    }
                ]], query_schema, {variables = {fields = {'echo'}}})
            end
    )

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar_inputObject(
                object: { nested_object: { field: $field } }
            )
        }
    ]], query_schema, {
        variables = {field = 'echo'},
    }), {test_custom_type_scalar_inputObject = 'echo'})

    t.assert_error_msg_equals(
            'Variable "field" type mismatch: ' ..
            'the variable type "NonNull(String)" is not compatible with the argument type '..
            '"CustomString"',
            function()
                check_request([[
                    query($field: String!) {
                        test_custom_type_scalar_inputObject(
                            object: { nested_object: { field: $field } }
                        )
                    }
                ]], query_schema, {variables = {fields = {'echo'}}})
            end
    )
end

function g.test_output_type_mismatch_error()
    local obj_type = types.object({
        name = 'ObjectWithValue',
        fields = {
            value = types.string,
        },
    })

    local nested_obj_type = types.object({
        name = 'NestedObjectWithValue',
        fields = {
            value = types.string,
        },
    })

    local complex_obj_type = types.object({
        name = 'ComplexObjectWithValue',
        fields = {
            values = types.list(nested_obj_type),
        },
    })

    local query_schema = {
        ['expected_nonnull_list'] = {
            kind = types.list(types.int.nonNull),
            resolve = function(_, _)
                return true
            end
        },
        ['expected_obj'] = {
            kind = obj_type,
            resolve = function(_, _)
                return true
            end
        },
        ['expected_list'] = {
            kind = types.list(types.int),
            resolve = function(_, _)
                return true
            end
        },
        ['expected_list_with_nested'] = {
            kind = types.list(complex_obj_type),
            resolve = function(_, _)
                return { values = true }
            end
        },
    }

    t.assert_error_msg_equals(
            'Expected "expected_nonnull_list" to be an "array", got "boolean"',
            function()
                check_request([[
                    query {
                        expected_nonnull_list
                    }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Expected "expected_obj" to be a "map", got "boolean"',
            function()
                check_request([[
                    query {
                        expected_obj { value }
                    }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Expected "expected_list" to be an "array", got "boolean"',
            function()
                check_request([[
                    query {
                        expected_list
                    }
                ]], query_schema)
            end
    )

    t.assert_error_msg_equals(
            'Expected "expected_list_with_nested" to be an "array", got "map"',
            function()
                check_request([[
                    query {
                        expected_list_with_nested { values { value } }
                    }
                ]], query_schema)
            end
    )
end

function g.test_default_values()
    local function decodeJson(value)
        if value ~= nil then
            return json.decode(value)
        end
        return value
    end

    local json_type = types.scalar({
        name = 'Json',
        description = 'Custom type with JSON decoding',
        serialize = json.encode,
        parseValue = decodeJson,
        parseLiteral = function(node)
            return decodeJson(node.value)
        end,
        isValueOfTheType = function(value) return type(value) == 'string' end,
    })

    local input_object = types.inputObject({
        name = 'default_input_object',
        fields = {
            field = types.string,
        }
    })

    local query_schema = {
        ['test_json_type'] = {
            kind = json_type,
            arguments = {
                field = json_type,
            },
            resolve = function(_, args)
                if args.field == nil then
                    return nil
                end
                assert(type(args.field) == 'table', "Field is not a table! ")
                assert(args.field.test ~= nil, "No field 'test' in object!")
                return args.field
            end,
        },
        ['test_default_value'] = {
            kind = types.string,
            arguments = {
                arg = types.string,
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg
            end
        },
        ['test_default_list'] = {
            kind = types.string,
            arguments = {
                arg = types.list(types.string),
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg[1]
            end
        },
        ['default_input_object'] = {
            kind = types.string,
            arguments = {
                arg = types.string,
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg.field
            end
        },
        ['test_default_object'] = {
            kind = types.string,
            arguments = {
                arg = input_object,
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg.field
            end
        },
        ['test_null'] = {
            kind = types.string,
            arguments = {
                arg = types.string,
                is_null = types.boolean,
            },
            resolve = function(_, args)
                assert(type(args.arg) ~= 'nil', 'default value should be "null"')
                if args.arg ~= nil then
                    return args.arg
                end
                if args.is_null then
                    return 'is_null'
                else
                    return 'not is_null'
                end
            end
        },
    }

    t.assert_equals(check_request([[
        query($arg: String = "default_value") {
            test_default_value(arg: $arg)
        }
    ]], query_schema, {
        variables = {},
    }), {test_default_value = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: String = "default_value") {
            test_default_value(arg: $arg)
        }
    ]], query_schema, {
        variables = {arg = box.NULL},
    }), {test_default_value = 'nil'})

    t.assert_equals(check_request([[
        query($arg: [String] = ["default_value"]) {
            test_default_list(arg: $arg)
        }
    ]], query_schema, {
        variables = {},
    }), {test_default_list = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: [String] = ["default_value"]) {
            test_default_list(arg: $arg)
        }
    ]], query_schema, {
        variables = {arg = box.NULL},
    }), {test_default_list = 'nil'})

    t.assert_equals(check_request([[
        query($arg: default_input_object = {field: "default_value"}) {
            test_default_object(arg: $arg)
        }
    ]], query_schema, {
        variables = {},
    }), {test_default_object = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: default_input_object = {field: "default_value"}) {
            test_default_object(arg: $arg)
        }
    ]], query_schema, {
        variables = {arg = box.NULL},
    }), {test_default_object = 'nil'})

    t.assert_equals(check_request([[
        query($field: Json = "{\"test\": 123}") {
            test_json_type(
                field: $field
            )
        }
    ]], query_schema, {
        variables = {},
    }), {test_json_type = '{"test":123}'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, {
        variables = {arg = 'abc'},
    }), {test_null = 'abc'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, {
        variables = {arg = box.NULL, is_null = true},
    }), {test_null = 'is_null'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, {
        variables = {is_null = false},
    }), {test_null = 'not is_null'})
end

function g.test_null()
    local query_schema = {
        ['test_null_nullable'] = {
            kind = types.string,
            arguments = {
                arg = types.string,
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg
            end,
        },
        ['test_null_non_nullable'] = {
            kind = types.string,
            arguments = {
                arg = types.string.nonNull,
            },
            resolve = function(_, args)
                if args.arg == nil then
                    return 'nil'
                end
                return args.arg
            end,
        },
    }

    t.assert_equals(check_request([[
        query {
            test_null_nullable(arg: null)
        }
    ]], query_schema, {
        variables = {},
    }), {test_null_nullable = 'nil'})

    t.assert_error_msg_equals(
            'Expected non-null for "NonNull(String)", got null',
            function()
                check_request([[
                    query {
                        test_null_non_nullable(arg: null)
                    }
                ]], query_schema)
            end
    )
end
