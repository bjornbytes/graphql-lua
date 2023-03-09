local t = require('luatest')
local g = t.group('unit')

local parse = require('graphql.parse').parse
local types = require('graphql.types')
local schema = require('graphql.schema')
local validate = require('graphql.validate').validate
local util = require('graphql.util')

function g.test_parse_comments()
    t.assert_error(parse('{a(b:"#")}').definitions, {})
end

function g.test_parse_document()
    t.assert_error(parse)
    t.assert_error(parse, 'foo')
    t.assert_error(parse, 'query')
    t.assert_error(parse, 'query{} foo')
end

function g.test_parse_operation_shorthand()
    local operation = parse('{a}').definitions[1]
    t.assert_equals(operation.kind, 'operation')
    t.assert_equals(operation.name, nil)
    t.assert_equals(operation.operation, 'query')
end

function g.test_parse_operation_operationType()
    local operation = parse('query{a}').definitions[1]
    t.assert_equals(operation.operation, 'query')

    operation = parse('mutation{a}').definitions[1]
    t.assert_equals(operation.operation, 'mutation')

    t.assert_error(parse, 'kneeReplacement{b}')
end

function g.test_parse_operation_name()
    local operation = parse('query{a}').definitions[1]
    t.assert_equals(operation.name, nil)

    operation = parse('query queryName{a}').definitions[1]
    t.assert_not_equals(operation.name, nil)
    t.assert_equals(operation.name.value, 'queryName')
end

function g.test_parse_operation_variableDefinitions()
    t.assert_error(parse, 'query(){b}')
    t.assert_error(parse, 'query(x){b}')

    local operation = parse('query name($a:Int,$b:Int){c}').definitions[1]
    t.assert_equals(operation.name.value, 'name')
    t.assert_not_equals(operation.variableDefinitions, nil)
    t.assert_equals(#operation.variableDefinitions, 2)

    operation = parse('query($a:Int,$b:Int){c}').definitions[1]
    t.assert_not_equals(operation.variableDefinitions, nil)
    t.assert_equals(#operation.variableDefinitions, 2)
end

function g.test_parse_operation_directives()
    local operation = parse('query{a}').definitions[1]
    t.assert_equals(operation.directives, nil)

    operation = parse('query @a{b}').definitions[1]
    t.assert_not_equals(operation.directives, nil)

    operation = parse('query name @a{b}').definitions[1]
    t.assert_not_equals(operation.directives, nil)

    operation = parse('query ($a:Int) @a {b}').definitions[1]
    t.assert_not_equals(operation.directives, nil)

    operation = parse('query name ($a:Int) @a {b}').definitions[1]
    t.assert_not_equals(operation.directives, nil)
end

function g.test_parse_fragmentDefinition_fragmentName()
    t.assert_error(parse, 'fragment {a}')
    t.assert_error(parse, 'fragment on x {a}')
    t.assert_error(parse, 'fragment on on x {a}')

    local fragment = parse('fragment x on y { a }').definitions[1]
    t.assert_equals(fragment.kind, 'fragmentDefinition')
    t.assert_equals(fragment.name.value, 'x')
end

function g.test_parse_fragmentDefinition_typeCondition()
    t.assert_error(parse, 'fragment x {c}')

    local fragment = parse('fragment x on y { a }').definitions[1]
    t.assert_equals(fragment.typeCondition.name.value, 'y')
end

function g.test_parse_fragmentDefinition_selectionSet()
    t.assert_error(parse, 'fragment x on y')

    local fragment = parse('fragment x on y { a }').definitions[1]
    t.assert_not_equals(fragment.selectionSet, nil)
end

function g.test_parse_selectionSet()
    t.assert_error(parse, '{')
    t.assert_error(parse, '}')

    local selectionSet = parse('{a}').definitions[1].selectionSet
    t.assert_equals(selectionSet.kind, 'selectionSet')
    t.assert_equals(selectionSet.selections, {{kind = "field", name = {kind = "name", value = "a"}}})

    selectionSet = parse('{a b}').definitions[1].selectionSet
    t.assert_equals(#selectionSet.selections, 2)
end

function g.test_parse_field_name()
    t.assert_error(parse, '{$a}')
    t.assert_error(parse, '{@a}')
    t.assert_error(parse, '{.}')
    t.assert_error(parse, '{,}')

    local field = parse('{a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(field.kind, 'field')
    t.assert_equals(field.name.value, 'a')
end

function g.test_parse_field_alias()
    t.assert_error(parse, '{a:b:}')
    t.assert_error(parse, '{a:b:c}')
    t.assert_error(parse, '{:a}')

    local field = parse('{a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(field.alias, nil)

    field = parse('{a:b}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.alias, nil)
    t.assert_equals(field.alias.kind, 'alias')
    t.assert_equals(field.alias.name.value, 'a')
    t.assert_equals(field.name.value, 'b')
end

function g.test_parse_field_arguments()
    t.assert_error(parse, '{a()}')

    local field = parse('{a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(field.arguments, nil)

    field = parse('{a(b:false)}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.arguments, nil)
end

function g.test_parse_field_directives()
    t.assert_error(parse, '{a@skip(b:false)(c:true)}')

    local field = parse('{a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(field.directives, nil)

    field = parse('{a@skip}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.directives, nil)

    field = parse('{a(b:1)@skip}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.directives, nil)
end

function g.test_parse_field_selectionSet()
    t.assert_error(parse, '{{}}')

    local field = parse('{a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(field.selectionSet, nil)

    field = parse('{a { b } }').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.selectionSet, nil)

    field = parse('{a{a}}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.selectionSet, nil)

    field = parse('{a(b:1)@skip{a}}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(field.selectionSet, nil)
end

function g.test_parse_fragmentSpread_name()
    t.assert_error(parse, '{..a}')
    t.assert_error(parse, '{...}')

    local fragmentSpread = parse('{...a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(fragmentSpread.kind, 'fragmentSpread')
    t.assert_equals(fragmentSpread.name.value, 'a')
end

function g.test_parse_fragmentSpread_directives()
    t.assert_error(parse, '{...a@}')

    local fragmentSpread = parse('{...a}').definitions[1].selectionSet.selections[1]
    t.assert_equals(fragmentSpread.directives, nil)

    fragmentSpread = parse('{...a@skip}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(fragmentSpread.directives, nil)
end

function g.test_parse_inlineFragment_typeCondition()
    t.assert_error(parse, '{...on{}}')

    local inlineFragment = parse('{...{ a }}').definitions[1].selectionSet.selections[1]
    t.assert_equals(inlineFragment.kind, 'inlineFragment')
    t.assert_equals(inlineFragment.typeCondition, nil)

    inlineFragment = parse('{...on a{ b }}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(inlineFragment.typeCondition, nil)
    t.assert_equals(inlineFragment.typeCondition.name.value, 'a')
end

function g.test_parse_inlineFragment_directives()
    t.assert_error(parse, '{...on a @ {}}')
    local inlineFragment = parse('{...{ a }}').definitions[1].selectionSet.selections[1]
    t.assert_equals(inlineFragment.directives, nil)

    inlineFragment = parse('{...@skip{ a }}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(inlineFragment.directives, nil)

    inlineFragment = parse('{...on a@skip { a }}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(inlineFragment.directives, nil)
end

function g.test_parse_inlineFragment_selectionSet()
    t.assert_error(parse, '{... on a}')

    local inlineFragment = parse('{...{a}}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(inlineFragment.selectionSet, nil)

    inlineFragment = parse('{... on a{b}}').definitions[1].selectionSet.selections[1]
    t.assert_not_equals(inlineFragment.selectionSet, nil)
end

function g.test_parse_arguments()
    t.assert_error(parse, '{a()}')

    local arguments = parse('{a(b:1)}').definitions[1].selectionSet.selections[1].arguments
    t.assert_equals(#arguments, 1)

    arguments = parse('{a(b:1 c:1)}').definitions[1].selectionSet.selections[1].arguments
    t.assert_equals(#arguments, 2)
end

function g.test_parse_argument()
    t.assert_error(parse, '{a(b)}')
    t.assert_error(parse, '{a(@b)}')
    t.assert_error(parse, '{a($b)}')
    t.assert_error(parse, '{a(b::)}')
    t.assert_error(parse, '{a(:1)}')
    t.assert_error(parse, '{a(b:)}')
    t.assert_error(parse, '{a(:)}')
    t.assert_error(parse, '{a(b c)}')

    local argument = parse('{a(b:1)}').definitions[1].selectionSet.selections[1].arguments[1]
    t.assert_equals(argument.kind, 'argument')
    t.assert_equals(argument.name.value, 'b')
    t.assert_equals(argument.value.value, '1')
end

function g.test_parse_directives()
    t.assert_error(parse, '{a@}')
    t.assert_error(parse, '{a@@}')

    local directives = parse('{a@b}').definitions[1].selectionSet.selections[1].directives
    t.assert_equals(#directives, 1)

    directives = parse('{a@b(c:1)@d}').definitions[1].selectionSet.selections[1].directives
    t.assert_equals(#directives, 2)
end

function g.test_parse_directive()
    t.assert_error(parse, '{a@b()}')

    local directive = parse('{a@b}').definitions[1].selectionSet.selections[1].directives[1]
    t.assert_equals(directive.kind, 'directive')
    t.assert_equals(directive.name.value, 'b')
    t.assert_equals(directive.arguments, nil)

    directive = parse('{a@b(c:1)}').definitions[1].selectionSet.selections[1].directives[1]
    t.assert_not_equals(directive.arguments, nil)
end

function g.test_parse_variableDefinitions()
    t.assert_error(parse, 'query(){}')
    t.assert_error(parse, 'query(a){}')
    t.assert_error(parse, 'query(@a){}')
    t.assert_error(parse, 'query($a){}')

    local variableDefinitions = parse('query($a:Int){ a }').definitions[1].variableDefinitions
    t.assert_equals(#variableDefinitions, 1)

    variableDefinitions = parse('query($a:Int $b:Int){ a }').definitions[1].variableDefinitions
    t.assert_equals(#variableDefinitions, 2)
end

function g.test_parse_variableDefinition_variable()
    local variableDefinition = parse('query($a:Int){ b }').definitions[1].variableDefinitions[1]
    t.assert_equals(variableDefinition.kind, 'variableDefinition')
    t.assert_equals(variableDefinition.variable.name.value, 'a')
end

function g.test_parse_variableDefinition_type()
    t.assert_error(parse, 'query($a){}')
    t.assert_error(parse, 'query($a:){}')
    t.assert_error(parse, 'query($a Int){}')

    local variableDefinition = parse('query($a:Int){b}').definitions[1].variableDefinitions[1]
    t.assert_equals(variableDefinition.type.name.value, 'Int')
end

function g.test_parse_variableDefinition_defaultValue()
    t.assert_error(parse, 'query($a:Int=){}')

    local variableDefinition = parse('query($a:Int){b}').definitions[1].variableDefinitions[1]
    t.assert_equals(variableDefinition.defaultValue, nil)

    variableDefinition = parse('query($a:Int=1){c}').definitions[1].variableDefinitions[1]
    t.assert_not_equals(variableDefinition.defaultValue, nil)
end

local function run(input, result, type)
    local value = parse('{x(y:' .. input .. ')}').definitions[1].selectionSet.selections[1].arguments[1].value
    if type then
        t.assert_equals(value.kind, type)
    end
    if result then
        t.assert_equals(value.value, result)
    end
    return value
end

function g.test_parse_value_variable()
    t.assert_error(parse, '{x(y:$)}')
    t.assert_error(parse, '{x(y:$a$)}')

    local value = run('$a')
    t.assert_equals(value.kind, 'variable')
    t.assert_equals(value.name.value, 'a')
end

function g.test_parse_value_int()
    t.assert_error(parse, '{x(y:01)}')
    t.assert_error(parse, '{x(y:-01)}')
    t.assert_error(parse, '{x(y:--1)}')
    t.assert_error(parse, '{x(y:+0)}')

    run('0', '0', 'int')
    run('-0', '-0', 'int')
    run('1234', '1234', 'int')
    run('-1234', '-1234', 'int')
end

function g.test_parse_value_float()
    t.assert_error(parse, '{x(y:.1)}')
    t.assert_error(parse, '{x(y:1.)}')
    t.assert_error(parse, '{x(y:1..)}')
    t.assert_error(parse, '{x(y:0e1.0)}')

    run('0.0', '0.0', 'float')
    run('-0.0', '-0.0', 'float')
    run('12.34', '12.34', 'float')
    run('1e0', '1e0', 'float')
    run('1e3', '1e3', 'float')
    run('1.0e3', '1.0e3', 'float')
    run('1.0e+3', '1.0e+3', 'float')
    run('1.0e-3', '1.0e-3', 'float')
    run('1.00e-30', '1.00e-30', 'float')
end

function g.test_parse_value_boolean()
    run('true', 'true', 'boolean')
    run('false', 'false', 'boolean')
end

function g.test_parse_value_string()
    t.assert_error(parse, '{x(y:")}')
    t.assert_error(parse, '{x(y:\'\')}')
    t.assert_error(parse, '{x(y:"\n")}')

    run('"yarn"', 'yarn', 'string')
    run('"th\\"read"', 'th"read', 'string')
end

function g.test_parse_value_enum()
    run('a', 'a', 'enum')
end

function g.test_parse_value_list()
    t.assert_error(parse, '{x(y:[)}')

    local value = run('[]')
    t.assert_equals(value.values, {})

    value = run('[a 1]')
    t.assert_equals(value, {
        kind = 'list',
        values = {
            {
                kind = 'enum',
                value = 'a'
            },
            {
                kind = 'int',
                value = '1'
            }
        }
    })

    value = run('[a [b] c]')
    t.assert_equals(value, {
        kind = 'list',
        values = {
            {
                kind = 'enum',
                value = 'a'
            },
            {
                kind = 'list',
                values = {
                    {
                        kind = 'enum',
                        value = 'b'
                    }
                }
            },
            {
                kind = 'enum',
                value = 'c'
            }
        }
    })
end

function g.test_parse_value_object()
    t.assert_error(parse, '{x(y:{a})}')
    t.assert_error(parse, '{x(y:{a:})}')
    t.assert_error(parse, '{x(y:{a::})}')
    t.assert_error(parse, '{x(y:{1:1})}')
    t.assert_error(parse, '{x(y:{"foo":"bar"})}')

    local value = run('{}')
    t.assert_equals(value.kind, 'inputObject')
    t.assert_equals(value.values, {})

    value = run('{a:1}')
    t.assert_equals(value.values, {
        {
            name = 'a',
            value = {
                kind = 'int',
                value = '1'
            }
        }
    })

    value = run('{a:1 b:2}')
    t.assert_equals(#value.values, 2)
end

function g.test_parse_namedType()
    t.assert_error(parse, 'query($a:$b){c}')

    local namedType = parse('query($a:b){ c }').definitions[1].variableDefinitions[1].type
    t.assert_equals(namedType.kind, 'namedType')
    t.assert_equals(namedType.name.value, 'b')
end

function g.test_parse_listType()
    t.assert_error(parse, 'query($a:[]){ b }')

    local listType = parse('query($a:[b]){ c }').definitions[1].variableDefinitions[1].type
    t.assert_equals(listType.kind, 'listType')
    t.assert_equals(listType.type.kind, 'namedType')
    t.assert_equals(listType.type.name.value, 'b')

    listType = parse('query($a:[[b]]){ c }').definitions[1].variableDefinitions[1].type
    t.assert_equals(listType.kind, 'listType')
    t.assert_equals(listType.type.kind, 'listType')
end

function g.test_parse_nonNullType()
    t.assert_error(parse, 'query($a:!){ b }')
    t.assert_error(parse, 'query($a:b!!){ c }')

    local nonNullType = parse('query($a:b!){ c }').definitions[1].variableDefinitions[1].type
    t.assert_equals(nonNullType.kind, 'nonNullType')
    t.assert_equals(nonNullType.type.kind, 'namedType')
    t.assert_equals(nonNullType.type.name.value, 'b')

    nonNullType = parse('query($a:[b]!) { c }').definitions[1].variableDefinitions[1].type
    t.assert_equals(nonNullType.kind, 'nonNullType')
    t.assert_equals(nonNullType.type.kind, 'listType')
end

local dogCommand = types.enum({
    name = 'DogCommand',
    values = {
        SIT = true,
        DOWN = true,
        HEEL = true
    }
})

local pet = types.interface({
    name = 'Pet',
    fields = {
        name = types.string.nonNull,
        nickname = types.int
    }
})

local dog = types.object({
    name = 'Dog',
    interfaces = { pet },
    fields = {
        name = types.string,
        nickname = types.string,
        barkVolume = types.int,
        doesKnowCommand = {
            kind = types.boolean.nonNull,
            arguments = {
                dogCommand = dogCommand.nonNull
            }
        },
        isHouseTrained = {
            kind = types.boolean.nonNull,
            arguments = {
                atOtherHomes = types.boolean
            }
        },
        complicatedField = {
            kind = types.boolean,
            arguments = {
                complicatedArgument = types.inputObject({
                    name = 'complicated',
                    fields = {
                        x = types.string,
                        y = types.integer,
                        z = types.inputObject({
                            name = 'alsoComplicated',
                            fields = {
                                x = types.string,
                                y = types.integer
                            }
                        })
                    }
                })
            }
        }
    }
})

local sentient = types.interface({
    name = 'Sentient',
    fields = {
        name = types.string.nonNull
    }
})

local alien = types.object({
    name = 'Alien',
    interfaces = sentient,
    fields = {
        name = types.string.nonNull,
        homePlanet = types.string
    }
})

local human = types.object({
    name = 'Human',
    fields = {
        name = types.string.nonNull
    }
})

local cat = types.object({
    name = 'Cat',
    fields = {
        name = types.string.nonNull,
        nickname = types.string,
        meowVolume = types.int
    }
})

local catOrDog = types.union({
    name = 'CatOrDog',
    types = { cat, dog }
})

local dogOrHuman = types.union({
    name = 'DogOrHuman',
    types = { dog, human }
})

local humanOrAlien = types.union({
    name = 'HumanOrAlien',
    types = { human, alien }
})

local query = types.object({
    name = 'Query',
    fields = {
        dog = {
            kind = dog,
            args = {
                name = {
                    kind = types.string
                }
            }
        },
        cat = cat,
        pet = pet,
        sentient = sentient,
        catOrDog = catOrDog,
        humanOrAlien = humanOrAlien,
        dogOrHuman = dogOrHuman,
    }
})

local schema_instance = schema.create({ query = query })
local function expectError(message, document)
    if not message then
        validate(schema_instance, parse(document))
    else
        t.assert_error_msg_contains(message, validate, schema_instance, parse(document))
    end
end

function g.test_rules_uniqueOperationNames()
    -- errors if two operations have the same name
    expectError('Multiple operations exist named', [[
        query foo { cat { name }  }
        query foo { cat { name } }
    ]])

    -- passes if all operations have different names
    expectError(nil, [[
        query foo { cat { name } }
        query bar { cat { name } }
    ]])
end

function g.test_rules_loneAnonymousOperation()
    local message = 'Cannot have more than one operation when'

    -- fails if there is more than one operation and one of them is anonymous'
    expectError(message, [[
        query { cat { name } }
        query named { cat { name }  }
    ]])

    expectError(message, [[
        query named { cat { name } }
        query { cat { name } }
    ]])

    expectError(message, [[
        query { cat { name } }
        query { cat { name } }
    ]])

    -- passes if there is one anonymous operation
    expectError(nil, '{ cat { name } }')

    -- passes if there are two named operations
    expectError(nil, [[
        query one { cat { name } }
        query two { cat { name } }
    ]])
end

function g.test_rules_fieldsDefinedOnType()
    local message = 'is not defined on type'

    -- fails if a field does not exist on an object type
    expectError(message, '{ doggy { name } }')
    expectError(message, '{ dog { age } }')

    -- passes if all fields exist on object types
    expectError(nil, '{ dog { name } }')

    -- understands aliases
    expectError(nil, '{ doggy: dog { name } }')
    expectError(message, '{ dog: doggy { name } }')
end

function g.test_rules_argumentsDefinedOnType()
    local message = 'Non-existent argument'

    -- passes if no arguments are supplied
    expectError(nil, '{ dog { isHouseTrained } }')

    -- errors if an argument name does not match the schema
    expectError(message, [[{
      dog {
        doesKnowCommand(doggyCommand: SIT)
      }
    }]])

    -- errors if an argument is supplied to a field that takes none
    expectError(message, [[{
      dog {
        name(truncateToLength: 32)
      }
    }]])

    -- passes if all argument names match the schema
    expectError(nil, [[{
      dog {
        doesKnowCommand(dogCommand: SIT)
      }
    }]])
end

function g.test_rules_scalarFieldsAreLeaves()
    local message = 'cannot have subselections'

    -- fails if a scalar field has a subselection
    expectError(message, '{ dog { name { firstLetter } } }')

    -- passes if all scalar fields are leaves
    expectError(nil, '{ dog { name nickname } }')
end

function g.test_rules_compositeFieldsAreNotLeaves()
    local message = 'must have subselections'

    -- fails if an object is a leaf
    expectError(message, '{ dog }')

    -- fails if an interface is a leaf
    expectError(message, '{ pet }')

    -- fails if a union is a leaf
    expectError(message, '{ catOrDog }')

    -- passes if all composite types have subselections
    expectError(nil, '{ dog { name } pet { name } }')
end

function g.test_rules_unambiguousSelections()
    -- fails if two fields with identical response keys have different types
    expectError('Type name mismatch', [[{
        dog {
          barkVolume
          barkVolume: name
        }
    }]])

    -- fails if two fields have different argument sets
    expectError('Argument mismatch', [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand(dogCommand: DOWN)
        }
    }]])

    -- passes if fields are identical
    expectError(nil, [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand: doesKnowCommand(dogCommand: SIT)
        }
    }]])
end

function g.test_rules_uniqueArgumentNames()
    local message = 'Encountered multiple arguments named'

    -- fails if a field has two arguments with the same name
    expectError(message, [[{
      dog {
        doesKnowCommand(dogCommand: SIT, dogCommand: DOWN)
      }
    }]])
end

function g.test_rules_argumentsOfCorrectType()
    -- fails if an argument has an incorrect type
    expectError('Expected enum value', [[{
      dog {
        doesKnowCommand(dogCommand: 4)
      }
    }]])
end

function g.test_rules_requiredArgumentsPresent()
    local message = 'was not supplied'

    -- fails if a non-null argument is not present
    expectError(message, [[{
      dog {
        doesKnowCommand
      }
    }]])
end

function g.test_rules_uniqueFragmentNames()
    local message = 'Encountered multiple fragments named'

    -- fails if there are two fragment definitions with the same name
    expectError(message, [[
      query { dog { ...nameFragment } }
      fragment nameFragment on Dog { name }
      fragment nameFragment on Dog { name }
    ]])

    -- passes if all fragment definitions have different names
    expectError(nil, [[
      query { dog { ...one ...two } }
      fragment one on Dog { name }
      fragment two on Dog { name }
    ]])
end

function g.test_rules_fragmentHasValidType()
    -- fails if a framgent refers to a non-composite type
    expectError('Fragment type must be an Object, Interface, or Union',
            'fragment f on DogCommand { name }')

    -- fails if a fragment refers to a non-existent type
    expectError('Fragment refers to non-existent type', 'fragment f on Hyena { a }')

    -- passes if a fragment refers to a composite type
    expectError(nil, '{ dog { ...f } } fragment f on Dog { name }')
end

function g.test_rules_noUnusedFragments()
    local message = 'was not used'

    -- fails if a fragment is not used
    expectError(message, 'fragment f on Dog { name }')
end

function g.test_rules_fragmentSpreadTargetDefined()
    local message = 'Fragment spread refers to non-existent'

    -- fails if the fragment does not exist
    expectError(message, '{ dog { ...f } }')
end

function g.test_rules_fragmentDefinitionHasNoCycles()
    local message = 'Fragment definition has cycles'

    -- fails if a fragment spread has cycles
    expectError(message, [[
      { dog { ...f } }
      fragment f on Dog { ...g }
      fragment g on Dog { ...h }
      fragment h on Dog { ...f }
    ]])
end

function g.test_rules_fragmentSpreadIsPossible()
    local message = 'Fragment type condition is not possible'

    -- fails if a fragment type condition refers to a different object than the parent object
    expectError(message, [[
      { dog { ...f } }
      fragment f on Cat { name }
    ]])


    -- fails if a fragment type condition refers to an interface that the parent object does not implement
    expectError(message, [[
      { dog { ...f } }
      fragment f on Sentient { name }
    ]])


    -- fails if a fragment type condition refers to a union that the parent object does not belong to
    expectError(message, [[
      { dog { ...f } }
      fragment f on HumanOrAlien { name }
    ]])

end

function g.test_rules_uniqueInputObjectFields()
    local message = 'Multiple input object fields named'

    -- fails if an input object has two fields with the same name
    expectError(message, [[
      {
        dog {
          complicatedField(complicatedArgument: {x: "hi", x: "hi"})
        }
      }
    ]])


    -- passes if an input object has nested fields with the same name
    expectError(nil, [[
      {
        dog {
          complicatedField(complicatedArgument: {x: "hi", z: {x: "hi"}})
        }
      }
    ]])

end

function g.test_rules_directivesAreDefined()
    local message = 'Unknown directive'

    -- fails if a directive does not exist
    expectError(message, 'query @someRandomDirective { op }')


    -- passes if directives exists
    expectError(nil, 'query @skip { dog { name } }')
end

function g.test_types_isValueOfTheType_for_scalars()
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

    t.assert_error(function()
        types.scalar({
            name = 'MyString',
            description = 'Custom string type',
            serialize = coerceString,
            parseValue = coerceString,
            parseLiteral = function(node)
                return coerceString(node.value)
            end,
        })
    end)

    local CustomString = types.scalar({
        name = 'MyString',
        description = 'Custom string type',
        serialize = coerceString,
        parseValue = coerceString,
        parseLiteral = function(node)
            return coerceString(node.value)
        end,
        isValueOfTheType = isString,
    })
    t.assert_equals(CustomString.__type, 'Scalar')
end

function g.test_types_for_different_schemas()
    local object_1 = types.object({
        name = 'Object',
        fields = {
            long_1 = types.long,
            string_1 = types.string,
        },
        schema = '1',
    })

    local query_1 = types.object({
        name = 'Query',
        fields = {
            object = {
                kind = object_1,
                args = {
                    name = {
                        string = types.string
                    }
                }
            },
            object_list = types.list('Object'),
        },
        schema = '1',
    })

    local object_2 = types.object({
        name = 'Object',
        fields = {
            long_2 = types.long,
            string_2 = types.string,
        },
        schema = '2',
    })

    local query_2 = types.object({
        name = 'Query',
        fields = {
            object = {
                kind = object_2,
                args = {
                    name = {
                        string = types.string
                    }
                }
            },
            object_list = types.list('Object'),
        },
        schema = '2',
    })

    local schema_1 = schema.create({query = query_1}, '1')
    local schema_2 = schema.create({query = query_2}, '2')

    validate(schema_1, parse([[
         query { object { long_1 string_1 } }
    ]]))

    validate(schema_2, parse([[
         query { object { long_2 string_2 } }
    ]]))

    validate(schema_1, parse([[
         query { object_list { long_1 string_1 } }
    ]]))

    validate(schema_2, parse([[
         query { object_list { long_2 string_2 } }
    ]]))

    -- Errors
    t.assert_error_msg_contains('Field "long_2" is not defined on type "Object"',
            validate, schema_1, parse([[query { object { long_2 string_1 } }]]))
    t.assert_error_msg_contains('Field "string_2" is not defined on type "Object"',
            validate, schema_1, parse([[query { object { long_1 string_2 } }]]))

    t.assert_error_msg_contains('Field "long_2" is not defined on type "Object"',
            validate, schema_1, parse([[query { object_list { long_2 string_1 } }]]))
    t.assert_error_msg_contains('Field "string_2" is not defined on type "Object"',
            validate, schema_1, parse([[query { object_list { long_1 string_2 } }]]))
end

function g.test_boolean_coerce()
    local query = types.object({
        name = 'Query',
        fields = {
            test_boolean = {
                kind = types.boolean.nonNull,
                arguments = {
                    value = types.boolean,
                    non_null_value = types.boolean.nonNull,
                }
            },
        }
    })

    local test_schema = schema.create({query = query})

    validate(test_schema, parse([[ { test_boolean(value: true, non_null_value: true) } ]]))
    validate(test_schema, parse([[ { test_boolean(value: false, non_null_value: false) } ]]))
    validate(test_schema, parse([[ { test_boolean(value: null, non_null_value: true) } ]]))

    -- Errors
    t.assert_error_msg_contains('Could not coerce value "True" with type "enum" to type boolean',
            validate, test_schema, parse([[ { test_boolean(value: True) } ]]))
    t.assert_error_msg_contains('Could not coerce value "123" with type "int" to type boolean',
            validate, test_schema, parse([[ { test_boolean(value: 123) } ]]))
    t.assert_error_msg_contains('Could not coerce value "value" with type "string" to type boolean',
            validate, test_schema, parse([[ { test_boolean(value: "value") } ]]))
end

function g.test_util_map_name()
    local res = util.map_name(nil, nil)
    t.assert_equals(res, {})

    res = util.map_name({ { name = 'a' }, { name = 'b' }, }, function(v) return v end)
    t.assert_equals(res, {a = {name = 'a'}, b = {name = 'b'}})

    res = util.map_name({ entry_a = { name = 'a' }, entry_b = { name = 'b' }, }, function(v) return v end)
    t.assert_equals(res, {a = {name = 'a'}, b = {name = 'b'}})
end

function g.test_util_find_by_name()
    local res = util.find_by_name({}, 'var')
    t.assert_equals(res, nil)

    res = util.find_by_name({ { name = 'avr' } }, 'var')
    t.assert_equals(res, nil)

    res = util.find_by_name({ { name = 'avr', value = 1 }, { name = 'var', value = 2 } }, 'var')
    t.assert_equals(res, { name = 'var', value = 2 })

    res = util.find_by_name(
        {
            entry1 = { name = 'avr', value = 1 },
            entry2 = { name = 'var', value = 2 }
        },
        'var')
    t.assert_equals(res, { name = 'var', value = 2 })
end

g.test_version = function()
    t.assert_type(require('graphql')._VERSION, 'string')
end

function g.test_is_array()
    t.assert_equals(util.is_array({[3] = 'a', [1] = 'b', [6] = 'c'}), true)
    t.assert_equals(util.is_array({[3] = 'a', [1] = 'b', [7] = 'c'}), true)
    t.assert_equals(util.is_array({[3] = 'a', nil, [6] = 'c'}), true)
    t.assert_equals(util.is_array({[3] = 'a', nil, [7] = 'c'}), true)
    t.assert_equals(util.is_array({[0] = 'a', [1] = 'b', [6] = 'c'}), true)
    t.assert_equals(util.is_array({[-1] = 'a', [1] = 'b', [6] = 'c'}), false)
    t.assert_equals(util.is_array({[3] = 'a', b = 'b', [6] = 'c'}), false)
    t.assert_equals(util.is_array({}), true)
    t.assert_equals(util.is_array(), false)
    t.assert_equals(util.is_array(''), false)
    t.assert_equals(util.is_array({a = 'a', b = 'b', c = 'c'}), false)
    t.assert_equals(util.is_array({a = 'a', nil, c = 'c'}), false)
end
