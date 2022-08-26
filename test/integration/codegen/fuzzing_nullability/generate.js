const { graphql, buildSchema } = require('graphql');

const nil = 'nil'
const box = {NULL: 'box.NULL'}

const Nullable = 'Nullable'
const NonNullable = 'NonNullable'

const graphql_types = {
    "boolean_true": {
        "var_type": 'Boolean',
        "value": true,
        "default": false,
    },
    "boolean_false": {
        "var_type": 'Boolean',
        "value": false,
        "default": true,
    },
    "float": {
        "var_type": 'Float',
        "value": 1.1111111,
        "default": 0,
    },
    "int": {
        "var_type": 'Int',
        "value": 2**30,
        "default": 0,
    },
    "id": {
        "var_type": 'ID',
        "value": '00000000-0000-0000-0000-000000000000',
        "default": '11111111-1111-1111-1111-111111111111',
    },
    "enum": {
        "graphql_type": `
        enum MyEnum {
            a
            b
        }
        `,
        "var_type": 'MyEnum',
        "value": `b`,
        "default": `a`,
    },
}

const Lua_to_JS_error = [
    {
        "regex": /^"Expected value of type \\\"(?<type>[a-zA-Z]+)\!\\\", found null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(${groups.type})\\\", got null"`
        }
    },
    {
        "regex": /^"Expected value of type \\\"\[(?<type>[a-zA-Z]+)\]\!\\\", found null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(List(${groups.type}))\\\", got null"`
        }
    },
    {
        "regex": /^"Expected value of type \\\"\[(?<type>[a-zA-Z]+)\!\]\\\", found null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"List(NonNull(${groups.type}))\\\", got null"`
        }
    },
    {
        "regex": /^"Expected value of type \\\"\[(?<type>[a-zA-Z]+)\!\]\!\\\", found null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(List(NonNull(${groups.type})))\\\", got null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of required type \\\"(?<type>[a-zA-Z]+)\!\\\" was not provided\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of non-null type \\\"(?<type>[a-zA-Z]+)\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"(?<type1>[a-zA-Z]+)\\\" used in position expecting type \\\"(?<type2>[a-zA-Z]+)\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"${groups.type1}\\\" is not compatible with the argument type \\\"NonNull(${groups.type2})\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" got invalid value null at \\\"var1\[0\]\\\"; Expected non-nullable type \\\"(?<type>[a-zA-Z]+)\!\\\" not to be null\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1[1]\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of non-null type \\\"\[(?<type>[a-zA-Z]+)\!\]\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of required type \\\"\[(?<type>[a-zA-Z]+)\!\]\!\\\" was not provided\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\]\!\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\!\]\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"NonNull(List(${groups.type1}))\\\" is not compatible with the argument type \\\"NonNull(List(NonNull(${groups.type2})))\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\!\]\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\!\]\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"List(NonNull(${groups.type1}))\\\" is not compatible with the argument type \\\"NonNull(List(NonNull(${groups.type2})))\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\]\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\!\]\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"List(${groups.type1})\\\" is not compatible with the argument type \\\"NonNull(List(NonNull(${groups.type2})))\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of non-null type \\\"\[(?<type1>[a-zA-Z]+)\]\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of required type \\\"\[(?<type1>[a-zA-Z]+)\]\!\\\" was not provided\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" expected to be non-null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\!\]\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\]\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"List(NonNull(${groups.type1}))\\\" is not compatible with the argument type \\\"NonNull(List(${groups.type2}))\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\]\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\]\!\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"List(${groups.type1})\\\" is not compatible with the argument type \\\"NonNull(List(${groups.type2}))\\\""`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\]\!\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\!\]\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"NonNull(List(${groups.type1}))\\\" is not compatible with the argument type \\\"List(NonNull(${groups.type2}))\\\""`
        }
    },
    {
        "regex": /^"Argument \\\"arg1\\\" of non-null type \\\"(?<type1>[a-zA-Z]+)\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(${groups.type1})\\\", got null"`
        }
    },
    {
        "regex": /^"Argument \\\"arg1\\\" of non-null type \\\"\[(?<type1>[a-zA-Z]+)\]\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(List(${groups.type1}))\\\", got null"`
        }
    },
    {
        "regex": /^"Argument \\\"arg1\\\" of non-null type \\\"\[(?<type1>[a-zA-Z]+)\!\]\!\\\" must not be null\."$/,
        "return": function(groups) {
            return `"Expected non-null for \\\"NonNull(List(NonNull(${groups.type1})))\\\", got null"`
        }
    },
    {
        "regex": /^"Variable \\\"\$var1\\\" of type \\\"\[(?<type1>[a-zA-Z]+)\]\\\" used in position expecting type \\\"\[(?<type2>[a-zA-Z]+)\!\]\\\"\."$/,
        "return": function(groups) {
            return `"Variable \\\"var1\\\" type mismatch: the variable type \\\"List(${groups.type1})\\\" is not compatible with the argument type \\\"List(NonNull(${groups.type2}))\\\""`
        }
    },
]

function JS_to_Lua_error_map_func(s) {
    let j = 0
    for (j = 0; j < Lua_to_JS_error.length; j++) {
        let found = s.match(Lua_to_JS_error[j].regex)

        if (found) {
            return Lua_to_JS_error[j].return(found.groups)
        }
    }

    return s
}

// == Build JS GraphQL objects ==

function get_JS_type_name(type) {
    if (type == 'list') {
        return 'list'
    }

    if (graphql_types[type]) {
        return graphql_types[type].var_type
    }

    return undefined
}

function get_JS_type_schema(type, inner_type) {
    if (inner_type !== null) {
        if (graphql_types[inner_type].graphql_type) {
            return graphql_types[inner_type].graphql_type
        }
        
        return ''
    }

    if (graphql_types[type]) {
        if (graphql_types[type].graphql_type) {
            return graphql_types[type].graphql_type
        }
        return ''
    }

    return ''
}

function get_JS_nullability(nullability) {
    if (nullability == NonNullable) {
        return `!`
    } else {
        return ``
    }
}

function get_JS_type(type, nullability,
                     inner_type, inner_nullability) {
    let js_type = get_JS_type_name(type)
    let js_nullability = get_JS_nullability(nullability)
    let js_inner_type = get_JS_type_name(inner_type)
    let js_inner_nullability = get_JS_nullability(inner_nullability)

    if (js_type === 'list') {
        return `[${js_inner_type}${js_inner_nullability}]${js_nullability}`
    } else {
        return `${js_type}${js_nullability}`
    }
}

function get_JS_value(type, inner_type, value, plain_nil_as_null) {
    if (Array.isArray(value)) {
        if (value[0] === nil) {
            return `[]`
        } else if (value[0] === box.NULL) {
            return `[null]`
        } else {
            if (inner_type == 'enum') {
                return `[${value}]`
            }
            return JSON.stringify(value)
        }
    } else {
        if (value === nil) {
            if (plain_nil_as_null) {
                return `null`
            } else {
                return ``
            }
        } else if (value === box.NULL) {
            return `null`
        } else {
            if (type == 'enum') {
                return value
            }
            return JSON.stringify(value)
        }
    }
}

function get_JS_default_value(type, inner_type, value) {
    return get_JS_value(type, inner_type, value, false)
}

function get_JS_argument_value(type, inner_type, value) {
    return get_JS_value(type, inner_type, value, true)
}

function build_schema(argument_type, argument_nullability,
                      argument_inner_type, argument_inner_nullability, 
                      argument_value,
                      variable_type, variable_nullability,
                      variable_inner_type, variable_inner_nullability, 
                      variable_value, variable_default) {
    let argument_str = get_JS_type(argument_type, argument_nullability,
                                   argument_inner_type, argument_inner_nullability)
    let additional_schema = get_JS_type_schema(argument_type, argument_inner_type)

    var schema_str = `${additional_schema}
        type result {
          arg1: ${argument_str}
        }

        type Query {
          test(arg1: ${argument_str}): result
        }
    `

  return schema_str;
};

function build_query(argument_type, argument_nullability,
                     argument_inner_type, argument_inner_nullability, 
                     argument_value,
                     variable_type, variable_nullability,
                     variable_inner_type, variable_inner_nullability, 
                     variable_value, variable_default) {
    if (variable_type !== null) {
        let variable_str = get_JS_type(variable_type, variable_nullability,
                                       variable_inner_type, variable_inner_nullability)

        let default_str = ``
        let js_variable_default = get_JS_default_value(variable_type, variable_inner_type, variable_default)
        if (js_variable_default !== ``) {
            default_str = ` = ${js_variable_default}`
        }

        return `query MyQuery($var1: ${variable_str}${default_str}) { test(arg1: $var1) { arg1 } }`
    } else {
        let js_argument_value = get_JS_argument_value(argument_type, argument_inner_type, argument_value)
        return `query MyQuery { test(arg1: ${js_argument_value}) { arg1 } }`
    }
};

function build_variables(argument_type, argument_nullability,
                         argument_inner_type, argument_inner_nullability, 
                         argument_value,
                         variable_type, variable_nullability,
                         variable_inner_type, variable_inner_nullability, 
                         variable_value, variable_default) {
    let variables = [];

    if (Array.isArray(variable_value)) {
        if (variable_value[0] == nil) {
            return {var1: []}
        } else if (variable_value[0] === box.NULL) {
            return {var1: [null]}
        } else {
            return {var1: variable_value}
        }
    }

    if (variable_value !== nil) {
        if (variable_value === box.NULL) {
            return {var1: null}
        } else {
            return {var1: variable_value}
        }
    }

    return []
}

var rootValue = {
    test: (args) => {
        return args;
    },
};

// == Build Lua GraphQL objects ==

var test_header = `-- THIS FILE WAS GENERATED AUTOMATICALLY
-- See generator script at tests/integration/codegen/fuzzing_nullability
-- This test compares library behaviour with reference JavaScript GraphQL
-- implementation. Do not change it manually if the behaviour has changed,
-- please interact with code generation script.

local json = require('json')
local types = require('graphql.types')

local t = require('luatest')
local g = t.group('fuzzing_nullability')

local helpers = require('test.helpers')

-- constants
local Nullable = true
local NonNullable = false

-- custom types
local my_enum = types.enum({
    name = 'MyEnum',
    values = {
        a = { value = 'a' },
        b = { value = 'b' },
    },
})

local graphql_types = {
    ['boolean_true'] = {
        graphql_type = types.boolean,
        var_type = 'Boolean',
        value = true,
        default = false,
    },
    ['boolean_false'] = {
        graphql_type = types.boolean,
        var_type = 'Boolean',
        value = false,
        default = true,
    },
    ['string'] = {
        graphql_type = types.string,
        var_type = 'String',
        value = 'Test string',
        default = 'Default Test string',
    },
    ['float'] = {
        graphql_type = types.float,
        var_type = 'Float',
        value = 1.1111111,
        default = 0,
    },
    ['int'] = {
        graphql_type = types.int,
        var_type = 'Int',
        value = 2^30,
        default = 0,
    },
    ['id'] = {
        graphql_type = types.id,
        var_type = 'ID',
        value = '00000000-0000-0000-0000-000000000000',
        default = '11111111-1111-1111-1111-111111111111',
    },
    ['enum'] = {
        graphql_type = my_enum,
        var_type = 'MyEnum',
        value = 'b',
        default = 'a',
    },
    -- For more types follow https://github.com/tarantool/graphql/issues/63
}

local function build_schema(argument_type, argument_nullability,
                            argument_inner_type, argument_inner_nullability,
                            argument_value,
                            variable_type, variable_nullability,
                            variable_inner_type, variable_inner_nullability,
                            variable_value, variable_default)
    local type
    if argument_type == 'list' then
        if argument_inner_nullability == NonNullable then
            type = types.list(types.nonNull(graphql_types[argument_inner_type].graphql_type))
        else
            type = types.list(graphql_types[argument_inner_type].graphql_type)
        end
        if argument_nullability == NonNullable then
            type = types.nonNull(type)
        end
    else
        if argument_nullability == NonNullable then
            type = types.nonNull(graphql_types[argument_type].graphql_type)
        else
            type = graphql_types[argument_type].graphql_type
        end
    end

    return {
        ['test'] = {
            kind = types.object({
                name = 'result',
                fields = {arg1 = type}
            }),
            arguments = {arg1 = type},
            resolve = function(_, args)
                return args
            end,
        }
    }
end

-- For more test cases follow https://github.com/tarantool/graphql/issues/63`
console.log(test_header)

function to_Lua(v) {
    if (v === null) {
        return `nil`
    }

    if (v === nil) {
        return `${v}`
    }

    if (v === box.NULL) {
        return `${v}`
    }

    if (v === Nullable) {
        return `${v}`
    }

    if (v === NonNullable) {
        return `${v}`
    }

    if (Array.isArray(v)) {
        if (v[0] === nil) {
            return '{}'
        } else if (v[0] === box.NULL) {
            return '{box.NULL}'
        } else {
            if (typeof v[0] === 'string' ) {
                return `{'${v[0]}'}`
            }

            return `{${v}}`
        }
    }

    if (typeof v === 'string' ) {
        return `'${v}'`
    }

    return `${v}`
}

function build_test_case(response, suite_name, i,
                         argument_type, argument_nullability,
                         argument_inner_type, argument_inner_nullability, 
                         argument_value,
                         variable_type, variable_nullability,
                         variable_inner_type, variable_inner_nullability, 
                         variable_value, variable_default,
                         query, schema_str) {
    let expected_data

    if (response.hasOwnProperty('data')) {
        let _expected_data = JSON.stringify(response.data)
        expected_data = `'${_expected_data}'`
    } else {
        expected_data = `nil`
    }

    let expected_error

    if (response.hasOwnProperty('errors')) {
        let _expected_error = JSON.stringify(response.errors[0].message)
        expected_error = JS_to_Lua_error_map_func(`${_expected_error}`)
    } else {
        expected_error = `nil`
    }

    let Lua_argument_type = to_Lua(argument_type)
    let Lua_argument_nullability = to_Lua(argument_nullability)
    let Lua_argument_inner_type = to_Lua(argument_inner_type)
    let Lua_argument_inner_nullability = to_Lua(argument_inner_nullability)

    let Lua_variable_type = to_Lua(variable_type)
    let Lua_variable_nullability = to_Lua(variable_nullability)
    let Lua_variable_inner_type = to_Lua(variable_inner_type)
    let Lua_variable_inner_nullability = to_Lua(variable_inner_nullability)


    let Lua_variable_default = to_Lua(variable_default)
    let Lua_argument_value = to_Lua(argument_value)
    let Lua_variable_value = to_Lua(variable_value)

    let type_in_name
    if (argument_inner_type !== null) {
        type_in_name = argument_inner_type
    } else {
        type_in_name = argument_type
    }

    return `
g.test_${suite_name}_${type_in_name}_${i} = function(g)
    local argument_type = ${Lua_argument_type}
    local argument_nullability = ${Lua_argument_nullability}
    local argument_inner_type = ${Lua_argument_inner_type}
    local argument_inner_nullability = ${Lua_argument_inner_nullability}
    local argument_value = ${Lua_argument_value}
    local variable_type = ${Lua_variable_type}
    local variable_nullability = ${Lua_variable_nullability}
    local variable_inner_type = ${Lua_variable_inner_type}
    local variable_inner_nullability = ${Lua_variable_inner_nullability}
    local variable_default = ${Lua_variable_default}
    local variable_value = ${Lua_variable_value}

    local query_schema = build_schema(argument_type, argument_nullability,
                                      argument_inner_type, argument_inner_nullability,
                                      argument_value,
                                      variable_type, variable_nullability,
                                      variable_inner_type, variable_inner_nullability,
                                      variable_value, variable_default)

    -- There is no explicit check that Lua query_schema is the same as JS query_schema.
    local reference_schema = [[${schema_str}]]

    local query = '${query}'

    local ok, res = pcall(helpers.check_request, query, query_schema, nil, nil, { variables = { var1 = variable_value }})

    local result, err
    if ok then
        result = json.encode(res)
    else
        err = res
    end

    local expected_data_json = ${expected_data}
    local expected_error_json = ${expected_error}

    if expected_error_json ~= nil and expected_data_json ~= nil then
        t.assert_equals(err, expected_error_json)
        t.xfail('See https://github.com/tarantool/graphql/issues/62')
    end

    t.assert_equals(result, expected_data_json)
    t.assert_equals(err, expected_error_json)
end`
}

async function build_suite(suite_name,
                     argument_type, argument_nullabilities,
                     argument_inner_type, argument_inner_nullabilities,
                     argument_values,
                     variable_type, variable_nullabilities,
                     variable_inner_type, variable_inner_nullabilities,
                     variable_values,
                     variable_defaults) {
    let i = 0

    if (argument_inner_nullabilities.length == 0) {
        // Non-list case
        let argument_inner_nullability = null
        let variable_inner_nullability = null

        if (variable_type == null) {
            // No variables case
            let variable_nullability = null
            let variable_value = null
            let variable_default = null

            argument_nullabilities.forEach( async function (argument_nullability) {
                argument_values.forEach( async function (argument_value)  {
                    let schema_str = build_schema(argument_type, argument_nullability,
                                              argument_inner_type, argument_inner_nullability,
                                              argument_value,
                                              variable_type, variable_nullability,
                                              variable_inner_type, variable_inner_nullability,
                                              variable_value, variable_default)
                    let schema = buildSchema(schema_str)

                    let query = build_query(argument_type, argument_nullability,
                                            argument_inner_type, argument_inner_nullability, 
                                            argument_value,
                                            variable_type, variable_nullability,
                                            variable_inner_type, variable_inner_nullability, 
                                            variable_value, variable_default)
                    

                    await graphql({
                        schema,
                        source: query,
                        rootValue,
                    }).then((response) => {
                        i = i + 1
                        console.log(build_test_case(response, suite_name, i,
                                               argument_type, argument_nullability,
                                               argument_inner_type, argument_inner_nullability, 
                                               argument_value,
                                               variable_type, variable_nullability,
                                               variable_inner_type, variable_inner_nullability, 
                                               variable_value, variable_default,
                                               query, schema_str))
                    })
                })
            })
        } else {
            // Variables case
            argument_nullabilities.forEach( async function (argument_nullability) {
                variable_nullabilities.forEach( async function (variable_nullability)  {
                    variable_values.forEach( async function (variable_value)  {
                        variable_defaults.forEach( async function (variable_default)  {
                            let argument_value = null

                            let schema_str = build_schema(argument_type, argument_nullability,
                                                      argument_inner_type, argument_inner_nullability, 
                                                      argument_value,
                                                      variable_type, variable_nullability,
                                                      variable_inner_type, variable_inner_nullability, 
                                                      variable_value, variable_default)
                            let schema = buildSchema(schema_str)

                            let query = build_query(argument_type, argument_nullability,
                                                    argument_inner_type, argument_inner_nullability, 
                                                    argument_value,
                                                    variable_type, variable_nullability,
                                                    variable_inner_type, variable_inner_nullability, 
                                                    variable_value, variable_default)

                            let variables = build_variables(argument_type, argument_nullability,
                                                            argument_inner_type, argument_inner_nullability, 
                                                            argument_value,
                                                            variable_type, variable_nullability,
                                                            variable_inner_type, variable_inner_nullability, 
                                                            variable_value, variable_default)
                            

                            await graphql({
                                schema,
                                source: query,
                                rootValue,
                                variableValues: variables
                            }).then((response) => {
                                i = i + 1
                                console.log(build_test_case(response, suite_name, i,
                                                            argument_type, argument_nullability,
                                                            argument_inner_type, argument_inner_nullability, 
                                                            argument_value,
                                                            variable_type, variable_nullability,
                                                            variable_inner_type, variable_inner_nullability, 
                                                            variable_value, variable_default,
                                                            query, schema_str))
                            })
                        })
                    })
                })
            })
        }

        return
    }

    // List case
    if (variable_type == null) {
        argument_nullabilities.forEach( async function (argument_nullability) {
            argument_inner_nullabilities.forEach( async function (argument_inner_nullability) {
                argument_values.forEach( async function (argument_value)  {
                    let variable_nullability = null
                    let variable_inner_nullability = null
                    let variable_value = null
                    let variable_default = null

                    let schema_str = build_schema(argument_type, argument_nullability,
                                              argument_inner_type, argument_inner_nullability, 
                                              argument_value,
                                              variable_type, variable_nullability,
                                              variable_inner_type, variable_inner_nullability, 
                                              variable_value, variable_default)
                    let schema = buildSchema(schema_str)

                    let query = build_query(argument_type, argument_nullability,
                                            argument_inner_type, argument_inner_nullability, 
                                            argument_value,
                                            variable_type, variable_nullability,
                                            variable_inner_type, variable_inner_nullability, 
                                            variable_value, variable_default)
                    
                    await graphql({
                        schema,
                        source: query,
                        rootValue,
                    }).then((response) => {
                        i = i + 1
                        console.log(build_test_case(response, suite_name, i,
                                                    argument_type, argument_nullability,
                                                    argument_inner_type, argument_inner_nullability, 
                                                    argument_value,
                                                    variable_type, variable_nullability,
                                                    variable_inner_type, variable_inner_nullability, 
                                                    variable_value, variable_default,
                                                    query, schema_str))
                    })
                })
            })
        })
    } else {
        argument_nullabilities.forEach( async function (argument_nullability) {
            argument_inner_nullabilities.forEach( async function (argument_inner_nullability) {
                variable_nullabilities.forEach( async function (variable_nullability) {
                    variable_inner_nullabilities.forEach( async function (variable_inner_nullability) {
                        variable_values.forEach( async function (variable_value)  {
                            variable_defaults.forEach( async function (variable_default)  {
                                let argument_value = null

                                let schema_str = build_schema(argument_type, argument_nullability,
                                                          argument_inner_type, argument_inner_nullability, 
                                                          argument_value,
                                                          variable_type, variable_nullability,
                                                          variable_inner_type, variable_inner_nullability, 
                                                          variable_value, variable_default)
                                let schema = buildSchema(schema_str)

                                let query = build_query(argument_type, argument_nullability,
                                                        argument_inner_type, argument_inner_nullability, 
                                                        argument_value,
                                                        variable_type, variable_nullability,
                                                        variable_inner_type, variable_inner_nullability, 
                                                        variable_value, variable_default)

                                let variables = build_variables(argument_type, argument_nullability,
                                                                argument_inner_type, argument_inner_nullability, 
                                                                argument_value,
                                                                variable_type, variable_nullability,
                                                                variable_inner_type, variable_inner_nullability, 
                                                                variable_value, variable_default)
                                    
                                await graphql({
                                    schema,
                                    source: query,
                                    rootValue,
                                    variableValues: variables
                                }).then((response) => {
                                    i = i + 1
                                    console.log(build_test_case(response, suite_name, i,
                                                                argument_type, argument_nullability,
                                                                argument_inner_type, argument_inner_nullability, 
                                                                argument_value,
                                                                variable_type, variable_nullability,
                                                                variable_inner_type, variable_inner_nullability, 
                                                                variable_value, variable_default,
                                                                query, schema_str))
                                })
                            })
                        })
                    })
                })
            })
        })
    }
}

let type
let type_desc

// == Non-list argument nullability ==
// 
// There is no way pass no value to the argument
// since `test(arg1)` is invalid syntax.
// We use `test(arg1: null)` for both nil and box.NULL,
// so the behavior will be the same for them.

Object.keys(graphql_types).forEach( (type) => {
    let type_desc = graphql_types[type]

    build_suite('nonlist_argument_nullability',
                type, [Nullable, NonNullable],
                null, [],
                [nil, box.NULL, type_desc.value],
                null, [],
                null, [],
                [],
                [])
})

// == List argument nullability ==
// 
// {nil} is the same as {} in Lua.

Object.keys(graphql_types).forEach( (type) => {
    let type_desc = graphql_types[type]

    build_suite('list_argument_nullability',
                'list', [Nullable, NonNullable],
                type, [Nullable, NonNullable],
                [nil, box.NULL, [nil], [box.NULL], [type_desc.value]],
                null, [],
                null, [],
                [],
                [])
})

// == Non-list argument with variable nullability ==

Object.keys(graphql_types).forEach( (type) => {
    let type_desc = graphql_types[type]

    build_suite('nonlist_argument_with_variables_nullability',
                type, [Nullable, NonNullable],
                null, [],
                [],
                type, [Nullable, NonNullable],
                null, [],
                [nil, box.NULL, type_desc.value],
                [nil, box.NULL, type_desc.default])
})

// == List argument with variable nullability ==
// 
// {nil} is the same as {} in Lua.

Object.keys(graphql_types).forEach( (type) => {
    let type_desc = graphql_types[type]


    build_suite('list_argument_with_variables_nullability',
                'list', [Nullable, NonNullable],
                type, [Nullable, NonNullable],
                [],
                'list', [Nullable, NonNullable],
                type, [Nullable, NonNullable],
                [nil, box.NULL, [nil], [box.NULL], [type_desc.value]],
                [nil, box.NULL, [nil], [box.NULL], [type_desc.default]])
})
