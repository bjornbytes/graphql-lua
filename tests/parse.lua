describe('parse', function()
  local parse = require 'graphql.parse'

  test('comments', function()
    local document

    document = parse('#')
    expect(document.definitions).to.equal({})

    document = parse('#{}')
    expect(document.definitions).to.equal({})
    expect(parse('{}').definitions).to_not.equal({})

    expect(function() parse('{}#a$b@') end).to_not.fail()
    expect(function() parse('{a(b:"#")}') end).to_not.fail()
  end)

  test('document', function()
    local document

    expect(function() parse() end).to.fail()
    expect(function() parse('foo') end).to.fail()
    expect(function() parse('query') end).to.fail()
    expect(function() parse('query{} foo') end).to.fail()

    document = parse('')
    expect(document.kind).to.equal('document')
    expect(document.definitions).to.equal({})

    document = parse('query{} mutation{} {}')
    expect(document.kind).to.equal('document')
    expect(#document.definitions).to.equal(3)
  end)

  describe('operation', function()
    local operation

    test('shorthand', function()
      operation = parse('{}').definitions[1]
      expect(operation.kind).to.equal('operation')
      expect(operation.name).to_not.exist()
      expect(operation.operation).to.equal('query')
    end)

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

    test('variableDefinitions', function()
      expect(function() parse('query(){}') end).to.fail()
      expect(function() parse('query(x){}') end).to.fail()

      operation = parse('query name($a:Int,$b:Int){}').definitions[1]
      expect(operation.name.value).to.equal('name')
      expect(operation.variableDefinitions).to.exist()
      expect(#operation.variableDefinitions).to.equal(2)

      operation = parse('query($a:Int,$b:Int){}').definitions[1]
      expect(operation.variableDefinitions).to.exist()
      expect(#operation.variableDefinitions).to.equal(2)
    end)

    test('directives', function()
      local operation = parse('query{}').definitions[1]
      expect(operation.directives).to_not.exist()

      local operation = parse('query @a{}').definitions[1]
      expect(#operation.directives).to.exist()

      local operation = parse('query name @a{}').definitions[1]
      expect(#operation.directives).to.exist()

      local operation = parse('query ($a:Int) @a {}').definitions[1]
      expect(#operation.directives).to.exist()

      local operation = parse('query name ($a:Int) @a {}').definitions[1]
      expect(#operation.directives).to.exist()
    end)
  end)

  describe('fragmentDefinition', function()
    local fragment

    test('fragmentName', function()
      expect(function() parse('fragment {}') end).to.fail()
      expect(function() parse('fragment on x {}') end).to.fail()
      expect(function() parse('fragment on on x {}') end).to.fail()

      fragment = parse('fragment x on y {}').definitions[1]
      expect(fragment.kind).to.equal('fragmentDefinition')
      expect(fragment.name.value).to.equal('x')
    end)

    test('typeCondition', function()
      expect(function() parse('fragment x {}') end).to.fail()

      fragment = parse('fragment x on y {}').definitions[1]
      expect(fragment.typeCondition.name.value).to.equal('y')
    end)

    test('selectionSet', function()
      expect(function() parse('fragment x on y') end).to.fail()

      fragment = parse('fragment x on y {}').definitions[1]
      expect(fragment.selectionSet).to.exist()
    end)
  end)

  test('selectionSet', function()
    local selectionSet

    expect(function() parse('{') end).to.fail()
    expect(function() parse('}') end).to.fail()

    selectionSet = parse('{}').definitions[1].selectionSet
    expect(selectionSet.kind).to.equal('selectionSet')
    expect(selectionSet.selections).to.equal({})

    selectionSet = parse('{a b}').definitions[1].selectionSet
    expect(#selectionSet.selections).to.equal(2)
  end)

  describe('field', function()
    local field

    test('name', function()
      expect(function() parse('{$a}') end).to.fail()
      expect(function() parse('{@a}') end).to.fail()
      expect(function() parse('{.}') end).to.fail()
      expect(function() parse('{,}') end).to.fail()

      field = parse('{a}').definitions[1].selectionSet.selections[1]
      expect(field.kind).to.equal('field')
      expect(field.name.value).to.equal('a')
    end)

    test('alias', function()
      expect(function() parse('{a:b:}') end).to.fail()
      expect(function() parse('{a:b:c}') end).to.fail()
      expect(function() parse('{:a}') end).to.fail()

      field = parse('{a}').definitions[1].selectionSet.selections[1]
      expect(field.alias).to_not.exist()

      field = parse('{a:b}').definitions[1].selectionSet.selections[1]
      expect(field.alias).to.exist()
      expect(field.alias.kind).to.equal('alias')
      expect(field.alias.name.value).to.equal('a')
      expect(field.name.value).to.equal('b')
    end)

    test('arguments', function()
      expect(function() parse('{a()}') end).to.fail()

      field = parse('{a}').definitions[1].selectionSet.selections[1]
      expect(field.arguments).to_not.exist()

      field = parse('{a(b:false)}').definitions[1].selectionSet.selections[1]
      expect(field.arguments).to.exist()
    end)

    test('directives', function()
      expect(function() parse('{a@skip(b:false)(c:true)}') end).to.fail()

      field = parse('{a}').definitions[1].selectionSet.selections[1]
      expect(field.directives).to_not.exist()

      field = parse('{a@skip}').definitions[1].selectionSet.selections[1]
      expect(field.directives).to.exist()

      field = parse('{a(b:1)@skip}').definitions[1].selectionSet.selections[1]
      expect(field.directives).to.exist()
    end)

    test('selectionSet', function()
      expect(function() parse('{{}}') end).to.fail()

      field = parse('{a}').definitions[1].selectionSet.selections[1]
      expect(field.selectionSet).to_not.exist()

      field = parse('{a{}}').definitions[1].selectionSet.selections[1]
      expect(field.selectionSet).to.exist()

      field = parse('{a{a}}').definitions[1].selectionSet.selections[1]
      expect(field.selectionSet).to.exist()

      field = parse('{a(b:1)@skip{a}}').definitions[1].selectionSet.selections[1]
      expect(field.selectionSet).to.exist()
    end)
  end)

  describe('fragmentSpread', function()
    local fragmentSpread

    test('name', function()
      expect(function() parse('{..a}') end).to.fail()
      expect(function() parse('{...}') end).to.fail()

      fragmentSpread = parse('{...a}').definitions[1].selectionSet.selections[1]
      expect(fragmentSpread.kind).to.equal('fragmentSpread')
      expect(fragmentSpread.name.value).to.equal('a')
    end)

    test('directives', function()
      expect(function() parse('{...a@}') end).to.fail()

      fragmentSpread = parse('{...a}').definitions[1].selectionSet.selections[1]
      expect(fragmentSpread.directives).to_not.exist()

      fragmentSpread = parse('{...a@skip}').definitions[1].selectionSet.selections[1]
      expect(fragmentSpread.directives).to.exist()
    end)
  end)

  describe('inlineFragment', function()
    local inlineFragment

    test('typeCondition', function()
      expect(function() parse('{...on{}}') end).to.fail()

      inlineFragment = parse('{...{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.kind).to.equal('inlineFragment')
      expect(inlineFragment.typeCondition).to_not.exist()

      inlineFragment = parse('{...on a{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.typeCondition).to.exist()
      expect(inlineFragment.typeCondition.name.value).to.equal('a')
    end)

    test('directives', function()
      expect(function() parse('{...on a @ {}}') end).to.fail()

      inlineFragment = parse('{...{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.directives).to_not.exist()

      inlineFragment = parse('{...@skip{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.directives).to.exist()

      inlineFragment = parse('{...on a@skip {}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.directives).to.exist()
    end)

    test('selectionSet', function()
      expect(function() parse('{... on a}') end).to.fail()

      inlineFragment = parse('{...{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.selectionSet).to.exist()

      inlineFragment = parse('{... on a{}}').definitions[1].selectionSet.selections[1]
      expect(inlineFragment.selectionSet).to.exist()
    end)
  end)

  test('arguments', function()
    local arguments

    expect(function() parse('{a()}') end).to.fail()

    arguments = parse('{a(b:1)}').definitions[1].selectionSet.selections[1].arguments
    expect(#arguments).to.equal(1)

    arguments = parse('{a(b:1 c:1)}').definitions[1].selectionSet.selections[1].arguments
    expect(#arguments).to.equal(2)
  end)

  test('argument', function()
    local argument

    expect(function() parse('{a(b)}') end).to.fail()
    expect(function() parse('{a(@b)}') end).to.fail()
    expect(function() parse('{a($b)}') end).to.fail()
    expect(function() parse('{a(b::)}') end).to.fail()
    expect(function() parse('{a(:1)}') end).to.fail()
    expect(function() parse('{a(b:)}') end).to.fail()
    expect(function() parse('{a(:)}') end).to.fail()
    expect(function() parse('{a(b c)}') end).to.fail()

    argument = parse('{a(b:1)}').definitions[1].selectionSet.selections[1].arguments[1]
    expect(argument.kind).to.equal('argument')
    expect(argument.name.value).to.equal('b')
    expect(argument.value.value).to.equal('1')
  end)

  test('directives', function()
    local directives

    expect(function() parse('{a@}') end).to.fail()
    expect(function() parse('{a@@}') end).to.fail()

    directives = parse('{a@b}').definitions[1].selectionSet.selections[1].directives
    expect(#directives).to.equal(1)

    directives = parse('{a@b(c:1)@d}').definitions[1].selectionSet.selections[1].directives
    expect(#directives).to.equal(2)
  end)

  test('directive', function()
    local directive

    expect(function() parse('{a@b()}') end).to.fail()

    directive = parse('{a@b}').definitions[1].selectionSet.selections[1].directives[1]
    expect(directive.kind).to.equal('directive')
    expect(directive.name.value).to.equal('b')
    expect(directive.arguments).to_not.exist()

    directive = parse('{a@b(c:1)}').definitions[1].selectionSet.selections[1].directives[1]
    expect(directive.arguments).to.exist()
  end)

  test('variableDefinitions', function()
    local variableDefinitions

    expect(function() parse('query(){}') end).to.fail()
    expect(function() parse('query(a){}') end).to.fail()
    expect(function() parse('query(@a){}') end).to.fail()
    expect(function() parse('query($a){}') end).to.fail()

    variableDefinitions = parse('query($a:Int){}').definitions[1].variableDefinitions
    expect(#variableDefinitions).to.equal(1)

    variableDefinitions = parse('query($a:Int $b:Int){}').definitions[1].variableDefinitions
    expect(#variableDefinitions).to.equal(2)
  end)

  describe('variableDefinition', function()
    local variableDefinition

    test('variable', function()
      variableDefinition = parse('query($a:Int){}').definitions[1].variableDefinitions[1]
      expect(variableDefinition.kind).to.equal('variableDefinition')
      expect(variableDefinition.variable.name.value).to.equal('a')
    end)

    test('type', function()
      expect(function() parse('query($a){}') end).to.fail()
      expect(function() parse('query($a:){}') end).to.fail()
      expect(function() parse('query($a Int){}') end).to.fail()

      variableDefinition = parse('query($a:Int){}').definitions[1].variableDefinitions[1]
      expect(variableDefinition.type.name.value).to.equal('Int')
    end)

    test('defaultValue', function()
      expect(function() parse('query($a:Int=){}') end).to.fail()

      variableDefinition = parse('query($a:Int){}').definitions[1].variableDefinitions[1]
      expect(variableDefinition.defaultValue).to_not.exist()

      variableDefinition = parse('query($a:Int=1){}').definitions[1].variableDefinitions[1]
      expect(variableDefinition.defaultValue).to.exist()
    end)
  end)

  describe('value', function()
    local value

    local function run(input, result, type)
      local value = parse('{x(y:' .. input .. ')}').definitions[1].selectionSet.selections[1].arguments[1].value
      if type then expect(value.kind).to.equal(type) end
      if result then expect(value.value).to.equal(result) end
      return value
    end

    test('variable', function()
      expect(function() parse('{x(y:$)}') end).to.fail()
      expect(function() parse('{x(y:$a$)}') end).to.fail()

      value = run('$a')
      expect(value.kind).to.equal('variable')
      expect(value.name.value).to.equal('a')
    end)

    test('int', function()
      expect(function() parse('{x(y:01)}') end).to.fail()
      expect(function() parse('{x(y:-01)}') end).to.fail()
      expect(function() parse('{x(y:--1)}') end).to.fail()
      expect(function() parse('{x(y:+0)}') end).to.fail()

      run('0', '0', 'int')
      run('-0', '-0', 'int')
      run('1234', '1234', 'int')
      run('-1234', '-1234', 'int')
    end)

    test('float', function()
      expect(function() parse('{x(y:.1)}') end).to.fail()
      expect(function() parse('{x(y:1.)}') end).to.fail()
      expect(function() parse('{x(y:1..)}') end).to.fail()
      expect(function() parse('{x(y:0e1.0)}') end).to.fail()

      run('0.0', '0.0', 'float')
      run('-0.0', '-0.0', 'float')
      run('12.34', '12.34', 'float')
      run('1e0', '1e0', 'float')
      run('1e3', '1e3', 'float')
      run('1.0e3', '1.0e3', 'float')
      run('1.0e+3', '1.0e+3', 'float')
      run('1.0e-3', '1.0e-3', 'float')
      run('1.00e-30', '1.00e-30', 'float')
    end)

    test('boolean', function()
      run('true', 'true', 'boolean')
      run('false', 'false', 'boolean')
    end)

    test('string', function()
      expect(function() parse('{x(y:")}') end).to.fail()
      expect(function() parse('{x(y:\'\')}') end).to.fail()
      expect(function() parse('{x(y:"\n")}') end).to.fail()

      run('"yarn"', 'yarn', 'string')
      run('"th\\"read"', 'th"read', 'string')
    end)

    test('enum', function()
      run('a', 'a', 'enum')
    end)

    test('list', function()
      expect(function() parse('{x(y:[)}') end).to.fail()

      value = run('[]')
      expect(value.values).to.equal({})

      value = run('[a 1]')
      expect(value).to.equal({
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
      expect(value).to.equal({
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
    end)

    test('object', function()
      expect(function() parse('{x(y:{a})}') end).to.fail()
      expect(function() parse('{x(y:{a:})}') end).to.fail()
      expect(function() parse('{x(y:{a::})}') end).to.fail()
      expect(function() parse('{x(y:{1:1})}') end).to.fail()
      expect(function() parse('{x(y:{"foo":"bar"})}') end).to.fail()

      value = run('{}')
      expect(value.kind).to.equal('inputObject')
      expect(value.values).to.equal({})

      value = run('{a:1}')
      expect(value.values).to.equal({
        {
          name = 'a',
          value = {
            kind = 'int',
            value = '1'
          }
        }
      })

      value = run('{a:1 b:2}')
      expect(#value.values).to.equal(2)
    end)
  end)

  test('namedType', function()
    expect(function() parse('query($a:$b){}') end).to.fail()

    local namedType = parse('query($a:b){}').definitions[1].variableDefinitions[1].type
    expect(namedType.kind).to.equal('namedType')
    expect(namedType.name.value).to.equal('b')
  end)

  test('listType', function()
    local listType

    expect(function() parse('query($a:[]){}') end).to.fail()

    listType = parse('query($a:[b]){}').definitions[1].variableDefinitions[1].type
    expect(listType.kind).to.equal('listType')
    expect(listType.type.kind).to.equal('namedType')
    expect(listType.type.name.value).to.equal('b')

    listType = parse('query($a:[[b]]){}').definitions[1].variableDefinitions[1].type
    expect(listType.kind).to.equal('listType')
    expect(listType.type.kind).to.equal('listType')
  end)

  test('nonNullType', function()
    local nonNullType

    expect(function() parse('query($a:!){}') end).to.fail()
    expect(function() parse('query($a:b!!){}') end).to.fail()

    nonNullType = parse('query($a:b!){}').definitions[1].variableDefinitions[1].type
    expect(nonNullType.kind).to.equal('nonNullType')
    expect(nonNullType.type.kind).to.equal('namedType')
    expect(nonNullType.type.name.value).to.equal('b')

    nonNullType = parse('query($a:[b]!){}').definitions[1].variableDefinitions[1].type
    expect(nonNullType.kind).to.equal('nonNullType')
    expect(nonNullType.type.kind).to.equal('listType')
  end)
end)
