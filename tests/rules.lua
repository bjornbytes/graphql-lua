local parse = require 'graphql.parse'
local validate = require 'graphql.validate'
local schema = require 'tests/data/schema'

local function expectError(message, document)
  if not message then
    expect(function() validate(schema, parse(document)) end).to_not.fail()
  else
    expect(function() validate(schema, parse(document)) end).to.fail.with(message)
  end
end

describe('rules', function()
  local document

  describe('uniqueOperationNames', function()
    local message = 'Multiple operations exist named'

    it('errors if two operations have the same name', function()
      expectError(message, [[
        query foo { }
        query foo { }
      ]])
    end)

    it('passes if all operations have different names', function()
      expectError(nil, [[
        query foo { }
        query bar { }
      ]])
    end)
  end)

  describe('loneAnonymousOperation', function()
    local message = 'Cannot have more than one operation when'

    it('fails if there is more than one operation and one of them is anonymous', function()
      expectError(message, [[
        query { }
        query named { }
      ]])

      expectError(message, [[
        query named { }
        query { }
      ]])

      expectError(message, [[
        query { }
        query { }
      ]])
    end)

    it('passes if there is one anonymous operation', function()
      expectError(nil, '{}')
    end)

    it('passes if there are two named operations', function()
      expectError(nil, [[
        query one {}
        query two {}
      ]])
    end)
  end)

  describe('fieldsDefinedOnType', function()
    local message = 'is not defined on type'

    it('fails if a field does not exist on an object type', function()
      expectError(message, '{ doggy { name } }')
      expectError(message, '{ dog { age } }')
    end)

    it('passes if all fields exist on object types', function()
      expectError(nil, '{ dog { name } }')
    end)

    it('understands aliases', function()
      expectError(nil, '{ doggy: dog { name } }')
      expectError(message, '{ dog: doggy { name } }')
    end)
  end)

  describe('argumentsDefinedOnType', function()
    local message = 'Non%-existent argument'

    it('passes if no arguments are supplied', function()
      expectError(nil, '{ dog { isHouseTrained } }')
    end)

    it('errors if an argument name does not match the schema', function()
      expectError(message, [[{
        dog {
          doesKnowCommand(doggyCommand: SIT)
        }
      }]])
    end)

    it('errors if an argument is supplied to a field that takes none', function()
      expectError(message, [[{
        dog {
          name(truncateToLength: 32)
        }
      }]])
    end)

    it('passes if all argument names match the schema', function()
      expectError(nil, [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
        }
      }]])
    end)
  end)

  describe('scalarFieldsAreLeaves', function()
    local message = 'Scalar values cannot have subselections'

    it('fails if a scalar field has a subselection', function()
      expectError(message, '{ dog { name { firstLetter } } }')
    end)

    it('passes if all scalar fields are leaves', function()
      expectError(nil, '{ dog { name nickname } }')
    end)
  end)

  describe('compositeFieldsAreNotLeaves', function()
    local message = 'Composite types must have subselections'
    
    it('fails if an object is a leaf', function()
      expectError(message, '{ dog }')
    end)

    it('fails if an interface is a leaf', function()
      expectError(message, '{ pet }')
    end)

    it('fails if a union is a leaf', function()
      expectError(message, '{ catOrDog }')
    end)

    it('passes if all composite types have subselections', function()
      expectError(nil, '{ dog { name } pet { } }')
    end)
  end)

  describe('unambiguousSelections', function()
    it('fails if two fields with identical response keys have different types', function()
      expectError('Type name mismatch', [[{
        dog {
          barkVolume
          barkVolume: name
        }
      }]])
    end)

    it('fails if two fields have different argument sets', function()
      expectError('Argument mismatch', [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand(dogCommand: DOWN)
        }
      }]])
    end)

    it('passes if fields are identical', function()
      expectError(nil, [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
          doesKnowCommand: doesKnowCommand(dogCommand: SIT)
        }
      }]])
    end)
  end)

  describe('uniqueArgumentNames', function()
    local message = 'Encountered multiple arguments named'

    it('fails if a field has two arguments with the same name', function()
      expectError(message, [[{
        dog {
          doesKnowCommand(dogCommand: SIT, dogCommand: DOWN)
        }
      }]])
    end)
  end)

  describe('argumentsOfCorrectType', function()
    it('fails if an argument has an incorrect type', function()
      expectError('Expected enum value', [[{
        dog {
          doesKnowCommand(dogCommand: 4)
        }
      }]])
    end)
  end)

  describe('requiredArgumentsPresent', function()
    local message = 'was not supplied'

    it('fails if a non-null argument is not present', function()
      expectError(message, [[{
        dog {
          doesKnowCommand
        }
      }]])
    end)
  end)

  describe('uniqueFragmentNames', function()
    local message = 'Encountered multiple fragments named'

    it('fails if there are two fragment definitions with the same name', function()
      expectError(message, [[
        query { dog { ...nameFragment } }
        fragment nameFragment on Dog { name }
        fragment nameFragment on Dog { name }
      ]])
    end)

    it('passes if all fragment definitions have different names', function()
      expectError(nil, [[
        query { dog { ...one ...two } }
        fragment one on Dog { name }
        fragment two on Dog { name }
      ]])
    end)
  end)

  describe('fragmentHasValidType', function()
    it('fails if a framgent refers to a non-composite type', function()
      expectError('Fragment type must be an Object, Interface, or Union', 'fragment f on DogCommand {}')
    end)

    it('fails if a fragment refers to a non-existent type', function()
      expectError('Fragment refers to non%-existent type', 'fragment f on Hyena {}')
    end)

    it('passes if a fragment refers to a composite type', function()
      expectError(nil, '{ dog { ...f } } fragment f on Dog {}')
    end)
  end)

  describe('noUnusedFragments', function()
    local message = 'was not used'

    it('fails if a fragment is not used', function()
      expectError(message, 'fragment f on Dog {}')
    end)
  end)

  describe('fragmentSpreadTargetDefined', function()
    local message = 'Fragment spread refers to non%-existent'

    it('fails if the fragment does not exist', function()
      expectError(message, '{ dog { ...f } }')
    end)
  end)

  describe('fragmentDefinitionHasNoCycles', function()
    local message = 'Fragment definition has cycles'

    it('fails if a fragment spread has cycles', function()
      expectError(message, [[
        { dog { ...f } }
        fragment f on Dog { ...g }
        fragment g on Dog { ...h }
        fragment h on Dog { ...f }
      ]])
    end)
  end)

  describe('fragmentSpreadIsPossible', function()
    local message = 'Fragment type condition is not possible'

    it('fails if a fragment type condition refers to a different object than the parent object', function()
      expectError(message, [[
        { dog { ...f } }
        fragment f on Cat { }
      ]])
    end)

    it('fails if a fragment type condition refers to an interface that the parent object does not implement', function()
      expectError(message, [[
        { dog { ...f } }
        fragment f on Sentient { }
      ]])
    end)

    it('fails if a fragment type condition refers to a union that the parent object does not belong to', function()
      expectError(message, [[
        { dog { ...f } }
        fragment f on HumanOrAlien { }
      ]])
    end)
  end)

  describe('uniqueInputObjectFields', function()
    local message = 'Multiple input object fields named'

    it('fails if an input object has two fields with the same name', function()
      expectError(message, [[
        {
          dog {
            complicatedField(complicatedArgument: {x: "hi", x: "hi"})
          }
        }
      ]])
    end)

    it('passes if an input object has nested fields with the same name', function()
      expectError(nil, [[
        {
          dog {
            complicatedField(complicatedArgument: {x: "hi", z: {x: "hi"}})
          }
        }
      ]])
    end)
  end)

  describe('directivesAreDefined', function()
    local message = 'Unknown directive'

    it('fails if a directive does not exist', function()
      expectError(message, 'query @someRandomDirective {}')
    end)

    it('passes if directives exists', function()
      expectError(nil, 'query @skip {}')
    end)
  end)
end)
