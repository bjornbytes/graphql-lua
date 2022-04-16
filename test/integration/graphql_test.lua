local json = require('json')
local types = require('graphql.types')
local schema = require('graphql.schema')
local parse = require('graphql.parse')
local validate = require('graphql.validate')
local execute = require('graphql.execute')
local util = require('graphql.util')
local introspection = require('test.integration.introspection')

local t = require('luatest')
local g = t.group('integration')

local test_schema_name = 'default'
local function check_request(query, query_schema, mutation_schema, directives, opts)
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

    local compiled_schema = schema.create(root, test_schema_name, opts)

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
    t.assert_equals(check_request(query, query_schema, nil, nil, {variables = variables}), {test = 'B22'})

    -- Negative tests
    local query = [[
        query ($arg: String! $arg2: String!) { test(arg: $arg, arg2: $arg2) }
    ]]

    t.assert_error_msg_equals(
            'Variable "arg2" expected to be non-null',
            function()
                check_request(query, query_schema, nil, nil, {variables = {}})
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
                check_request(query, query_schema, nil, nil, {variables = {}})
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
                ]], query_schema, nil, nil, { variables = {unknown_arg = ''}})
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
    ]], query_schema, nil, nil, {variables = {arg = {field = 'a'}}}), {simple_enum = 'a'})

    t.assert_error_msg_equals(
            'Wrong variable "arg.field" for the Enum "simple_enum" with value "d"',
            function()
                check_request([[
                    query($arg: simple_input_object) {
                        simple_enum(arg: $arg)
                    }
                ]], query_schema, nil, nil, {variables = {arg = {field = 'd'}}})
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
    ]], query_schema, nil, nil, {variables = {field = 'echo'}}), {test_nested_InputObject = 'echo'})

    t.assert_error_msg_equals(
            'Unused variable "field"',
            function()
                check_request([[
                    query($field: String!) {
                        test_nested_InputObject(
                            servers: [{ field: "not-variable" }]
                        )
                    }
                ]], query_schema, nil, nil, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($field: String!) {
            test_nested_list(
                servers: [$field]
            )
        }
    ]], query_schema, nil, nil, {variables = {field = 'echo'}}), {test_nested_list = 'echo'})

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
    ]], query_schema, nil, nil, {
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
                t.assert_type(args.field, 'table', "Field is not a table! ")
                t.assert_not_equals(args.field.test, nil, "No field 'test' in object!")
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
        ['test_json_type_list'] = {
            arguments = {
                array = types.list(json_type),
            },
            kind = types.list(json_type),
            resolve = function(_, args)
                if args.array == nil then
                    return nil
                end
                t.assert_type(args.array[1], 'table', "Array element is not a table! ")
                t.assert_not_equals(args.array[1].test, nil, "No field 'test' in array element!")
                return args.array
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
    ]], query_schema, nil, nil, {
        variables = {field = '{"test": 123}'},
    }), {test_json_type = '{"test":123}'})

    t.assert_equals(check_request([[
        query($field: Json) {
            test_json_type(
                field: $field
            )
        }
    ]], query_schema, nil, nil, {
        variables = {field = box.NULL},
    }), {test_json_type = 'null'})

    t.assert_equals(check_request([[
        query($array: [Json]) {
            test_json_type_list(
                array: $array
            )
        }
    ]], query_schema, nil, nil, {
        variables = {array = {json.encode({test = 123})}},
    }), {test_json_type_list = {'{"test":123}'}})

    t.assert_equals(check_request([[
        query {
            test_json_type(
                field: "null"
            )
        }
    ]], query_schema, nil, nil, {
        variables = {},
    }), {test_json_type = 'null'})

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar(
                field: $field
            )
        }
    ]], query_schema, nil, nil, {
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
                ]], query_schema, nil, nil, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar_list(
                fields: [$field]
            )
        }
    ]], query_schema, nil, nil, {
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
                ]], query_schema, nil, nil, {variables = {field = 'echo'}})
            end
    )

    t.assert_equals(check_request([[
        query($fields: [CustomString!]!) {
            test_custom_type_scalar_list(
                fields: $fields
            )
        }
    ]], query_schema, nil, nil, {
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
                ]], query_schema, nil, nil, {variables = {fields = {'echo'}}})
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
                ]], query_schema, nil, nil, {variables = {fields = {'echo'}}})
            end
    )

    t.assert_equals(check_request([[
        query($field: CustomString!) {
            test_custom_type_scalar_inputObject(
                object: { nested_object: { field: $field } }
            )
        }
    ]], query_schema, nil, nil, {
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
                ]], query_schema, nil, nil, {variables = {fields = {'echo'}}})
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
    ]], query_schema, nil, nil, {
        variables = {},
    }), {test_default_value = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: String = "default_value") {
            test_default_value(arg: $arg)
        }
    ]], query_schema, nil, nil, {
        variables = {arg = box.NULL},
    }), {test_default_value = 'nil'})

    t.assert_equals(check_request([[
        query($arg: [String] = ["default_value"]) {
            test_default_list(arg: $arg)
        }
    ]], query_schema, nil, nil, {
        variables = {},
    }), {test_default_list = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: [String] = ["default_value"]) {
            test_default_list(arg: $arg)
        }
    ]], query_schema, nil, nil, {
        variables = {arg = box.NULL},
    }), {test_default_list = 'nil'})

    t.assert_equals(check_request([[
        query($arg: default_input_object = {field: "default_value"}) {
            test_default_object(arg: $arg)
        }
    ]], query_schema, nil, nil, {
        variables = {},
    }), {test_default_object = 'default_value'})

    t.assert_equals(check_request([[
        query($arg: default_input_object = {field: "default_value"}) {
            test_default_object(arg: $arg)
        }
    ]], query_schema, nil, nil, {
        variables = {arg = box.NULL},
    }), {test_default_object = 'nil'})

    t.assert_equals(check_request([[
        query($field: Json = "{\"test\": 123}") {
            test_json_type(
                field: $field
            )
        }
    ]], query_schema, nil, nil, {
        variables = {},
    }), {test_json_type = '{"test":123}'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, nil, nil, {
        variables = {arg = 'abc'},
    }), {test_null = 'abc'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, nil, nil, {
        variables = {arg = box.NULL, is_null = true},
    }), {test_null = 'is_null'})

    t.assert_equals(check_request([[
        query($arg: String = null, $is_null: Boolean) {
            test_null(arg: $arg is_null: $is_null)
        }
    ]], query_schema, nil, nil, {
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
    ]], query_schema, nil, nil, {
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

function g.test_validation_non_null_argument_error()
    local function callback(_, _)
        return nil
    end

    local query_schema = {
        ['TestEntity'] = {
            kind = types.string,
            arguments = {
                insert = types.inputObject({
                    name = 'TestEntityInput',
                    fields = {
                        non_null = types.string.nonNull,
                    }
                }),
            },
            resolve = callback,
        }
    }

    t.assert_error_msg_contains(
            'Expected non-null',
            function()
                check_request([[
                    query QueryFail {
                        TestEntity(insert: {})
                    }
                ]], query_schema)
            end
    )

    t.assert_error_msg_contains(
            'Expected non-null',
            function()
                check_request([[
                    query QueryFail {
                        TestEntity(insert: {non_null: null})
                    }
                ]], query_schema)
            end
    )
end

function g.test_both_data_and_error_result()
    local query = [[{
        test_A: test(arg: "A")
        test_B: test(arg: "B")
    }]]

    local function callback(_, args)
        return args[1].value, {message = 'Simple error ' .. args[1].value}
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
    local data, errors = check_request(query, query_schema)
    t.assert_equals(data, {test_A = 'A', test_B = 'B'})
    t.assert_equals(errors,  {
        {message = 'Simple error A'},
        {message = 'Simple error B'},
    })

    query = [[{
        prefix {
            test_A: test(arg: "A")
            test_B: test(arg: "B")
        }
    }]]

    local function callback_external()
        return {}, {message = 'Simple error from external resolver'}
    end

    local function callback_internal(_, args)
        return args[1].value, {message = 'Simple error from internal resolver ' .. args[1].value}
    end

    query_schema = {
        ['prefix'] = {
            kind = types.object({
                name = 'prefix',
                fields = {
                    ['test'] = {
                        kind = types.string.nonNull,
                        arguments = {
                            arg = types.string.nonNull,
                            arg2 = types.string,
                            arg3 = types.int,
                            arg4 = types.long,
                        },
                        resolve = callback_internal,
                    }
                },
            }),
            arguments = {},
            resolve = callback_external,
        }
    }

    data, errors = check_request(query, query_schema)
    t.assert_equals(data, {prefix = {test_A = 'A', test_B = 'B'}})
    t.assert_equals(errors,  {
        {message = "Simple error from internal resolver A"},
        {message = "Simple error from internal resolver B"},
        {message = "Simple error from external resolver"},
    }, "Errors from each resolver were returned")
end

function g.test_introspection()
    local function callback(_, _)
        return nil
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

    local mutation_schema = {
        ['test_mutation'] = {
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

    local directives = {
        types.directive({
            name = 'custom',
            arguments = {},
            onQuery = true,
            onMutation = true,
            onField = true,
            onFragmentDefinition = true,
            onFragmentSpread = true,
            onInlineFragment = true,
            onVariableDefinition = true,
            onSchema = true,
            onScalar = true,
            onObject = true,
            onFieldDefinition = true,
            onArgumentDefinition = true,
            onInterface = true,
            onUnion = true,
            onEnum = true,
            onEnumValue = true,
            onInputObject = true,
            onInputFieldDefinition = true,
            isRepeatable = true,
        })
    }

    local data, errors = check_request(introspection.query, query_schema, mutation_schema, directives)
    t.assert_type(data, 'table')
    t.assert_equals(errors, nil)
end

function g.test_custom_directives()
    -- simple string directive
    local function callback(_, _, info)
        return require('json').encode(info.directives)
    end

    local query_schema = {
        ['prefix'] = {
            kind = types.object({
                name = 'prefix',
                fields = {
                    ['test'] = {
                        kind = types.string,
                        arguments = {
                            arg = types.string.nonNull,
                            arg2 = types.string,
                            arg3 = types.int,
                            arg4 = types.long,
                        },
                        resolve = callback,
                    }
                },
            }),
            arguments = {},
            resolve = function()
                return {}
            end,
        }
    }

    local directives = {
        types.directive({
            name = 'custom',
            arguments = {
                arg = types.string.nonNull,
            },
            onQuery = true,
            onMutation = true,
            onField = true,
            onFragmentDefinition = true,
            onFragmentSpread = true,
            onInlineFragment = true,
            onVariableDefinition = true,
            onSchema = true,
            onScalar = true,
            onObject = true,
            onFieldDefinition = true,
            onArgumentDefinition = true,
            onInterface = true,
            onUnion = true,
            onEnum = true,
            onEnumValue = true,
            onInputObject = true,
            onInputFieldDefinition = true,
            isRepeatable = true,
        })
    }

    local simple_query = [[query TEST{
        prefix {
            test_A: test(arg: "A")@custom(arg: "a")
        }
    }]]
    local data, errors = check_request(simple_query, query_schema, nil, directives)
    t.assert_equals(data, { prefix = { test_A = '{"custom":{"arg":"a"}}' }})
    t.assert_equals(errors, nil)

    local var_query = [[query TEST($arg: String){
        prefix {
            test_B: test(arg: "B")@custom(arg: $arg)
        }
    }]]
    data, errors = check_request(var_query, query_schema, nil, directives,
        {variables = {arg = 'echo'}})
    t.assert_equals(data, { prefix = { test_B = '{"custom":{"arg":"echo"}}' }})
    t.assert_equals(errors, nil)

    -- InputObject directives
    local Entity = types.inputObject({
        name = 'Entity',
        fields = {
            num = types.int,
            str = types.string,
        },
        schema = test_schema_name, -- add type to schema registry so it may be called by name
    })

    local function callback(_, args, info)
        local obj = args['arg']
        local dir = info.directives

        if dir ~= nil then
            local override = dir.override_v2 or dir.override or {}
            for k, v in pairs(override['arg']) do
                obj[k] = v
            end
        end

        return require('json').encode(obj)
    end

    query_schema = {
        ['test'] = {
            kind = types.string,
            arguments = {
                arg = Entity,
            },
            resolve = callback,
        }
    }

    directives = {
        types.directive({
            name = 'override',
            arguments = {
                arg = Entity,
            },
            onInputObject = true,
        })
    }

    local query = [[query TEST{
        test_C: test(arg: { num: 2, str: "s" })@override(arg: { num: 3, str: "s1" })
        test_D: test(arg: { num: 2, str: "s" })@override(arg: { num: 3 })
        test_E: test(arg: { num: 2, str: "s" })@override(arg: { str: "s1" })
        test_F: test(arg: { num: 2, str: "s" })@override(arg: { })
    }]]
    data, errors = check_request(query, query_schema, nil, directives)
    t.assert_equals(data, {
        test_C = '{"num":3,"str":"s1"}',
        test_D = '{"num":3,"str":"s"}',
        test_E = '{"num":2,"str":"s1"}',
        test_F = '{"num":2,"str":"s"}',
    })
    t.assert_equals(errors, nil)

    -- Check internal type resolver
    directives = {
        types.directive({
            name = 'override_v2',
            arguments = {
                arg = 'Entity', -- refer to type by name
            },
            onInputObject = true,
        })
    }

    query = [[query TEST{
        test_G: test(arg: { num: 2, str: "s" })@override_v2(arg: { num: 5, str: "news" })
    }]]

    data, errors = check_request(query, query_schema, nil, directives)
    t.assert_equals(data, { test_G = '{"num":5,"str":"news"}' })
    t.assert_equals(errors, nil)

    -- check custom directives with variables
    local variables = {num = 33}

    query = [[query TEST($num: Int, $str: String = "variable") {
        test_G: test(arg: { num: 2, str: "s" })@override_v2(arg: { num: $num, str: $str })
    }]]

    data, errors = check_request(query, query_schema, nil, directives, {variables = variables})
    t.assert_equals(data, { test_G = '{"num":33,"str":"variable"}' })
    t.assert_equals(errors, nil)
end

function g.test_specifiedByURL_scalar_field()
    local function callback(_, _)
        return nil
    end

    local custom_scalar = types.scalar({
        name = 'CustomInt',
        description = "The `CustomInt` scalar type represents non-fractional signed whole numeric values. " ..
                      "Int can represent values from -(2^31) to 2^31 - 1, inclusive.",
        serialize = function(value)
            return value
        end,
        parseLiteral = function(node)
            return node.value
        end,
        isValueOfTheType = function(_)
            return true
        end,
        specifiedByURL = 'http://localhost',
    })

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = custom_scalar,
            },
            resolve = callback,
        }
    }

    local data, errors = check_request(introspection.query, query_schema)
    local CustomInt_schema = util.find_by_name(data.__schema.types, 'CustomInt')
    t.assert_type(CustomInt_schema, 'table', 'CustomInt schema found on introspection')
    t.assert_equals(CustomInt_schema.specifiedByURL, 'http://localhost')
    t.assert_equals(errors, nil)
end

function g.test_specifiedBy_directive()
    local function callback(_, args, info)
        local v = args[1].value
        local dir = info.directives
        if dir ~= nil and dir.specifiedBy ~= nil then
            return { value = v, url = dir.specifiedBy.url }
        end

        return { value = v }
    end

    local custom_scalar = types.scalar({
        name = 'CustomInt',
        description = "The `CustomInt` scalar type represents non-fractional signed whole numeric values. " ..
                      "Int can represent values from -(2^31) to 2^31 - 1, inclusive.",
        serialize = function(value)
            return value
        end,
        parseLiteral = function(node)
            return node.value
        end,
        isValueOfTheType = function(_)
            return true
        end,
    })

    local query_schema = {
        ['test'] = {
            kind = custom_scalar,
            arguments = {
                arg = custom_scalar,
            },
            resolve = callback,
        }
    }

    local query = [[query {
        test_A: test(arg: 1)@specifiedBy(url: "http://localhost")
    }]]

    local data, errors = check_request(query, query_schema)
    t.assert_equals(data, { test_A = { url = "http://localhost", value = "1" } })
    t.assert_equals(errors, nil)
end

function g.test_descriptions()
    local function callback(_, _)
        return nil
    end

    local query_schema = {
        ['test_query'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = types.string,
                arg_described = {
                    kind = types.object({
                        name = 'test_object',
                        fields = {
                            object_arg_described = {
                                kind = types.string,
                                description = 'object argument'
                            },
                            object_arg = types.string,
                        },
                        kind = types.string,
                    }),
                    description = 'described query argument',
                }
            },
            resolve = callback,
            description = 'test query',
        }
    }

    local mutation_schema = {
        ['test_mutation'] = {
            kind = types.string.nonNull,
            arguments = {
                mutation_arg = types.string,
                mutation_arg_described = {
                    kind = types.inputObject({
                        name = 'test_input_object',
                        fields = {
                            input_object_arg_described = {
                                kind = types.string,
                                description = 'input object argument'
                            },
                            input_object_arg = types.string,
                        },
                        kind = types.string,
                    }),
                    description = 'described mutation argument',
                },
            },
            resolve = callback,
            description = 'test mutation',
        }
    }

    local data, errors = check_request(introspection.query, query_schema, mutation_schema)
    t.assert_equals(errors, nil)

    local test_query = util.find_by_name(data.__schema.types, 'Query')
    t.assert_equals(test_query.fields[1].description, 'test query')

    local arg_described = util.find_by_name(test_query.fields[1].args, 'arg_described')
    t.assert_equals(arg_described.description, 'described query argument')

    local test_object = util.find_by_name(data.__schema.types, 'test_object')
    local object_arg_described = util.find_by_name(test_object.fields, 'object_arg_described')
    t.assert_equals(object_arg_described.description, 'object argument')

    local test_mutation = util.find_by_name(data.__schema.types, 'Mutation')
    t.assert_equals(test_mutation.fields[1].description, 'test mutation')

    local mutation_arg_described = util.find_by_name(test_mutation.fields[1].args, 'mutation_arg_described')
    t.assert_equals(mutation_arg_described.description, 'described mutation argument')

    local test_input_object = util.find_by_name(data.__schema.types, 'test_input_object')
    local input_object_arg_described = util.find_by_name(test_input_object.inputFields, 'input_object_arg_described')
    t.assert_equals(input_object_arg_described.description, 'input object argument')
end

function g.test_schema_input_arg_described_with_kind()
    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = {
                    kind = types.string.nonNull,
                },
            },
            resolve = callback,
        }
    }

    local query = [[
        { test(arg: "A") }
    ]]

    local _, errors = check_request(query, query_schema, {})
    t.assert_equals(errors, nil)
end

function g.test_schema_input_arg_described_with_kind_variable_pass()
    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = {
                    kind = types.string.nonNull,
                },
            },
            resolve = callback,
        }
    }

    local query = [[
        query ($arg: String!) { test(arg: $arg) }
    ]]
    local variables = { arg = 'B' }

    local _, errors = check_request(query, query_schema, nil, nil, { variables = variables })
    t.assert_equals(errors, nil)
end

function g.test_arguments_default_values()
    local function callback(_, _)
        return nil
    end

    local mutation_schema = {
        ['test_mutation'] = {
            kind = types.string.nonNull,
            arguments = {
                mutation_arg = {
                    kind = types.string,
                    defaultValue = 'argument default value',
                },
                mutation_arg_defaults = {
                    kind = types.inputObject({
                        name = 'test_input_object',
                        fields = {
                            input_object_arg_defaults = {
                                kind = types.string,
                                defaultValue = 'input object argument default value'
                            },
                            input_object_arg = types.string,
                            nested_enum_arg_defaults = {
                                kind = types.enum({
                                    schema = schema,
                                    name = 'mode',
                                    values = {
                                        read = 'read',
                                        write = 'write',
                                    },
                                }),
                                defaultValue = 'write',
                            }
                        },
                        kind = types.string,
                    }),
                },
            },
            resolve = callback,
        }
    }

    local data, errors = check_request(introspection.query, nil, mutation_schema)
    t.assert_equals(errors, nil)

    local mutations = util.find_by_name(data.__schema.types, 'Mutation')
    local test_mutation = util.find_by_name(mutations.fields, 'test_mutation')
    local mutation_arg = util.find_by_name(test_mutation.args, 'mutation_arg')
    t.assert_equals(mutation_arg.defaultValue, 'argument default value')

    local test_input_object = util.find_by_name(data.__schema.types, 'test_input_object')
    local input_object_arg_defaults = util.find_by_name(test_input_object.inputFields, 'input_object_arg_defaults')
    t.assert_equals(input_object_arg_defaults.defaultValue, 'input object argument default value')

    local nested_enum_arg_defaults = util.find_by_name(test_input_object.inputFields, 'nested_enum_arg_defaults')
    t.assert_equals(nested_enum_arg_defaults.defaultValue, 'write')
end

function g.test_specifiedByURL_long_scalar()
    local query_schema = {
        ['test'] = {
            kind = types.string.nonNull,
            arguments = {
                arg = types.long,
            },
            resolve = '',
        }
    }

    local data, errors = check_request(introspection.query, query_schema)
    local long_type_schema = util.find_by_name(data.__schema.types, 'Long')
    t.assert_type(long_type_schema, 'table', 'Long scalar type found on introspection')
    t.assert_equals(long_type_schema.specifiedByURL, 'https://github.com/tarantool/graphql/wiki/Long')
    t.assert_equals(errors, nil)
end

function g.test_skip_include_directives()
    local function callback(_, _)
        return {
            uri = 'uri1',
            uris = {
                uri = 'uri2'
            }
        }
    end

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
            resolve = callback,
        }
    }

    -- check request without directives
    local data, errors = check_request('{test{uri uris{uri}}}', query_schema)
    t.assert_equals(errors, nil)
    t.assert_items_equals(data, {test = {uri = "uri1", uris = {uri = "uri2"}}})

    -- check request with directive: skip if == false
    data, errors = check_request(
        'query TEST($skip_field: Boolean){test{uri@skip(if: $skip_field) uris{uri}}}',
        query_schema,
        nil,
        nil,
        { variables = { skip_field = false }}
    )
    t.assert_equals(errors, nil)
    t.assert_items_equals(data, {test = {uri = "uri1", uris = {uri = "uri2"}}})

    -- check request with directive: skip if == true
    data, errors = check_request(
        'query TEST($skip_field: Boolean){test{uri@skip(if: $skip_field) uris{uri}}}',
        query_schema,
        nil,
        nil,
        { variables = { skip_field = true }}
    )
    t.assert_equals(errors, nil)
    t.assert_items_equals(data, {test = {uris = {uri = "uri2"}}})

    -- check request with directive: include if == false
    data, errors = check_request(
        'query TEST($include_field: Boolean){test{uri@include(if: $include_field) uris{uri}}}',
        query_schema,
        nil,
        nil,
        { variables = { include_field = false }}
    )
    t.assert_equals(errors, nil)
    t.assert_items_equals(data, {test = {uris = {uri = "uri2"}}})

    -- check request with directive: include if == true
    data, errors = check_request(
        'query TEST($include_field: Boolean){test{uri@include(if: $include_field) uris{uri}}}',
        query_schema,
        nil,
        nil,
        { variables = { include_field = true }}
    )
    t.assert_equals(errors, nil)
    t.assert_items_equals(data, {test = {uri = "uri1", uris = {uri = "uri2"}}})
end

-- test simultaneous usage of mutation and directive default values
function g.test_mutation_and_directive_arguments_default_values()
    local function callback(_, _)
        return nil
    end

    local mutation_schema = {
        ['test_mutation'] = {
            kind = types.string.nonNull,
            arguments = {
                object_arg = {
                    kind = types.inputObject({
                        name = 'test_input_object',
                        fields = {
                            nested = {
                                kind = types.string,
                                defaultValue = 'default Value',
                            },
                        },
                        kind = types.string,
                    }),
                },
                mutation_arg = {
                    kind = types.int,
                    defaultValue = 1,
                },

            },
            resolve = callback,
        }
    }

    local directives = {
        types.directive({
            schema = schema,
            name = 'timeout',
            description = 'Request execute timeout',
            arguments = {
                seconds = {
                    kind = types.int,
                    description = 'Request timeout (in seconds). Default: 1 second',
                    defaultValue = 1,
                },
            },
            onField = true,
        })
    }

    local root = {
        query = types.object({
            name = 'Query',
            fields = {},
        }),
        mutation = types.object({
            name = 'Mutation',
            fields = mutation_schema or {},
        }),
        directives = directives,
    }

    local compiled_schema = schema.create(root, test_schema_name)

    -- test that schema.typeMap is not corrupted when both mutation and
    -- directive default values used on the same argument type
    t.assert_equals(compiled_schema.typeMap['Int'].defaultValue, nil)
end

g.test_propagate_defaults_to_callback = function()
    local query = '{test_mutation}'

    local function callback(_, _, info)
        return json.encode({
            defaultValues = info.defaultValues,
            directivesDefaultValues = info.directivesDefaultValues,
        })
    end

    local input_object = types.inputObject({
        name = 'test_input_object',
        fields = {
            nested_int_arg = {
                kind = types.int,
                defaultValue = 2,
            },
            nested_string_arg = {
                kind = types.string,
                defaultValue = 'default nested value',
            },
            nested_boolean_arg = {
                kind = types.boolean,
                defaultValue = true,
            },
            nested_float_arg = {
                kind = types.float,
                defaultValue = 1.1,
            },
            nested_long_arg = {
                kind = types.long,
                defaultValue = 2^50,
            },
            nested_list_scalar_arg = {
                kind = types.list(types.string),
                -- defaultValue seems illogical
            }
        },
        kind = types.string,
    })

    local mutation_schema = {
        ['test_mutation'] = {
            kind = types.string.nonNull,
            arguments = {
                int_arg = {
                    kind = types.int,
                    defaultValue = 1,
                },
                string_arg = {
                    kind = types.string,
                    defaultValue = 'string_arg'
                },
                boolean_arg = {
                    kind = types.boolean,
                    defaultValue = false,
                },
                float_arg = {
                    kind = types.float,
                    defaultValue = 1.1,
                },
                long_arg = {
                    kind = types.long,
                    defaultValue = 2^50,
                },
                object_arg = {
                    kind = input_object,
                    -- defaultValue seems illogical
                },
                list_scalar_arg = {
                    kind = types.list(types.string),
                    -- defaultValue seems illogical
                }
            },
            resolve = callback,
        }
    }

    local directives = {
        types.directive({
            schema = schema,
            name = 'timeout',
            description = 'Request execute timeout',
            arguments = {
                int_arg = {
                    kind = types.int,
                    defaultValue = 1,
                },
                string_arg = {
                    kind = types.string,
                    defaultValue = 'string_arg'
                },
                boolean_arg = {
                    kind = types.boolean,
                    defaultValue = false,
                },
                float_arg = {
                    kind = types.float,
                    defaultValue = 1.1,
                },
                long_arg = {
                    kind = types.long,
                    defaultValue = 2^50,
                },
                object = input_object
            },
            onField = true,
        })
    }

    local result = {
        defaultValues = {
            boolean_arg = false,
            int_arg = 1,
            float_arg = 1.1,
            long_arg = 2^50,
            object_arg = {
                nested_boolean_arg = true,
                nested_float_arg = 1.1,
                nested_int_arg = 2,
                nested_long_arg = 2^50,
                nested_string_arg = "default nested value",
            },
            string_arg = "string_arg",
        },
        directivesDefaultValues = {
            timeout = {
                boolean_arg = false,
                float_arg = 1.1,
                int_arg = 1,
                long_arg = 2^50,
                object = {
                    nested_boolean_arg = true,
                    nested_float_arg = 1.1,
                    nested_int_arg = 2,
                    nested_long_arg = 2^50,
                    nested_string_arg = "default nested value",
                },
                string_arg = "string_arg",
            },
        },
    }

    local data, errors = check_request(
        query,
        mutation_schema,
        nil,
        directives,
        { defaultValues = true, directivesDefaultValues = true, }
    )

    t.assert_equals(errors, nil)
    t.assert_items_equals(json.decode(data.test_mutation), result)

    query = '{prefix{test_mutation}}'

    local mutation_schema_with_prefix = {
        ['prefix'] = {
            kind = types.object({
                name = 'prefix',
                fields = mutation_schema,
            }),
            arguments = {},
            resolve = function()
                return {}
            end,
        }
    }

    data, errors = check_request(
        query,
        mutation_schema_with_prefix,
        nil,
        directives,
        { defaultValues = true, directivesDefaultValues = true, }
    )
    t.assert_equals(errors, nil)
    t.assert_items_equals(json.decode(data.prefix.test_mutation), result)
end

-- gh-47: accept a cdata number as a value of a Float variable.
function g.test_cdata_number_as_float()
     local query = [[
        query ($x: Float!) { test(arg: $x) }
    ]]

    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.float.nonNull,
            arguments = {
                arg = types.float.nonNull,
            },
            resolve = callback,
        }
    }

    -- 2^64-1
    local variables = {x = 18446744073709551615ULL}
    local res = check_request(query, query_schema, nil, nil, {variables = variables})
    t.assert_type(res, 'table')
    t.assert_almost_equals(res.test, 18446744073709551615)
end

-- Accept a large number in a Float argument.
--
-- The test is created in the scope of gh-47, but it is not
-- strictly related to it: the issue is about interpreting
-- a cdata number in a **variable** as a `Float` value.
--
-- Here we check a large number, which is written verbatim as
-- an argument in a query. Despite that it is not what is
-- described in gh-47, it worth to have such a test.
function g.test_large_float_argument()
    -- 2^64-1
     local query = [[
        { test(arg: 18446744073709551615) }
    ]]

    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.float.nonNull,
            arguments = {
                arg = types.float.nonNull,
            },
            resolve = callback,
        }
    }

    local res = check_request(query, query_schema)
    t.assert_type(res, 'table')
    t.assert_almost_equals(res.test, 18446744073709551615)
end

-- http://spec.graphql.org/October2021/#sec-Float
--
-- > Non-finite floating-point internal values (NaN and Infinity) cannot be
-- > coerced to Float and must raise a field error.
function g.test_non_finite_float()
     local query = [[
        query ($x: Float!) { test(arg: $x) }
    ]]

    local function callback(_, args)
        return args[1].value
    end

    local query_schema = {
        ['test'] = {
            kind = types.float.nonNull,
            arguments = {
                arg = types.float.nonNull,
            },
            resolve = callback,
        }
    }

    local nan = 0 / 0
    local inf = 1 / 0
    local ninf = -inf

    for _, x in pairs({nan, inf, ninf}) do
        local variables = {x = x}
        t.assert_error_msg_content_equals(
            'Wrong variable "x" for the Scalar "Float"', check_request, query,
            query_schema, nil, nil, {variables = variables})
    end
end
