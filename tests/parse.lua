local parse = require 'parse'

describe('parse', function()
  test('nil', function()
    expect(function() parse(nil) end).to.fail()
  end)

  test('empty string', function()
    expect(parse('')).to.equal({
      kind = 'document',
      definitions = {}
    })
  end)

  test('shorthand operation', function()
    local operation = parse('{}').definitions[1]
    expect(operation.kind).to.equal('operation')
    expect(operation.name).to_not.exist()
    expect(operation.operation).to.equal('query')
  end)

  describe('operation', function()
    local operation

    test('operationType', function()
      operation = parse('query{}').definitions[1]
      expect(operation.operation).to.equal('query')

      operation = parse('mutation{}').definitions[1]
      expect(operation.operation).to.equal('mutation')

      expect(function() parse('kneeReplacement{}') end).to.fail()
    end)

    test('name', function()
      operation = parse('query{}').definitions[1]
      expect(operation.name).to_not.exist()

      operation = parse('query queryName{}').definitions[1]
      expect(operation.name).to.exist()
      expect(operation.name.value).to.equal('queryName')
    end)
  end)
end)
