local parse = require 'parse'
local validate = require 'validate'
local schema = require 'tests/data/schema'

local function run(query)
  validate(schema, parse(query))
end

describe('rules', function()
  describe('uniqueOperationNames', function()
    it('errors if two operations have the same name', function()
      local query = [[
        query foo { }
        query foo { }
      ]]

      expect(function() run(query) end).to.fail.with('Multiple operations exist named')
    end)

    it('passes if operations have different names', function()
      local query = [[
        query foo { }
        query bar { }
      ]]

      expect(function() run(query) end).to_not.fail()
    end)
  end)

  describe('argumentsDefinedOnType', function()
    it('passes if no arguments are supplied', function()
      local query = [[{
        dog {
          isHouseTrained
        }
      }]]

      expect(function() run(query) end).to_not.fail()
    end)

    it('errors if an argument name does not match the schema', function()
      local query = [[{
        dog {
          doesKnowCommand(doggyCommand: SIT)
        }
      }]]

      expect(function() run(query) end).to.fail.with('Non%-existent argument')
    end)

    it('errors if an argument is supplied to a field that takes none', function()
      local query = [[{
        dog {
          name(truncateToLength: 32)
        }
      }]]

      expect(function() run(query) end).to.fail.with('Non%-existent argument')
    end)

    it('passes if all argument names match the schema', function()
      local query = [[{
        dog {
          doesKnowCommand(dogCommand: SIT)
        }
      }]]

      expect(function() run(query) end).to_not.fail()
    end)
  end)
end)
