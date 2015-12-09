local parse = require 'parse'

describe('parse', function()
  it('errors if passed nil', function()
    expect(function() parse(nil) end).to.fail()
  end)

  it('returns a document with no definitions if passed an empty string', function()
    expect(parse('')).to.equal({
      kind = 'document',
      definitions = {}
    })
  end)
end)
