local lpeg = require 'lpeg'
local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Ct, Cmt, Cg, Cc, Cf, Cmt = lpeg.C, lpeg.Ct, lpeg.Cmt, lpeg.Cg, lpeg.Cc, lpeg.Cf, lpeg.Cmt

local line
local lastLinePos

local function pack(...)
  return { n = select('#', ...), ... }
end

-- Utility
local ws = Cmt(S(' \t\r\n') ^ 0, function(str, pos)
  str = str:sub(lastLinePos, pos)
  while str:find('\n') do
    line = line + 1
    lastLinePos = pos
    str = str:sub(str:find('\n') + 1)
  end

  return true
end)

local comma = P(',') ^ 0

local _ = V

local function maybe(pattern)
  if type(pattern) == 'string' then pattern = V(pattern) end
  return pattern ^ -1
end

local function list(pattern, min)
  if type(pattern) == 'string' then pattern = V(pattern) end
  min = min or 0
  return Ct((pattern * ws * comma * ws) ^ min)
end

-- Formatters
local function simpleValue(key)
  return function(value)
    return {
      kind = key,
      value = value
    }
  end
end

local cName = simpleValue('name')
local cInt = simpleValue('int')
local cFloat = simpleValue('float')
local cBoolean = simpleValue('boolean')
local cEnum = simpleValue('enum')

local cString = function(value)
  return {
    kind = 'string',
    value = value:gsub('\\"', '"')
  }
end

local function cList(value)
  return {
    kind = 'list',
    values = value
  }
end

local function cObjectField(name, value)
  return {
    name = name,
    value = value
  }
end

local function cObject(fields)
  return {
    kind = 'inputObject',
    values = fields
  }
end

local function cAlias(name)
  return {
    kind = 'alias',
    name = name
  }
end

local function cArgument(name, value)
  return {
    kind = 'argument',
    name = name,
    value = value
  }
end

local function cField(...)
  local tokens = pack(...)
  local field = { kind = 'field' }

  for i = 1, #tokens do
    local key = tokens[i].kind
    if not key then
      if tokens[i][1].kind == 'argument' then
        key = 'arguments'
      elseif tokens[i][1].kind == 'directive' then
        key = 'directives'
      end
    end

    field[key] = tokens[i]
  end

  return field
end

local function cSelectionSet(selections)
  return {
    kind = 'selectionSet',
    selections = selections
  }
end

local function cFragmentSpread(name, directives)
  return {
    kind = 'fragmentSpread',
    name = name,
    directives = directives
  }
end

local function cOperation(...)
  local args = pack(...)
  if args[1].kind == 'selectionSet' then
    return {
      kind = 'operation',
      operation = 'query',
      selectionSet = args[1]
    }
  else
    local result = {
      kind = 'operation',
      operation = args[1]
    }

    for i = 2, #args do
      local key = args[i].kind
      if not key then
        if args[i][1].kind == 'variableDefinition' then
          key = 'variableDefinitions'
        elseif args[i][1].kind == 'directive' then
          key = 'directives'
        end
      end

      result[key] = args[i]
    end

    return result
  end
end

local function cDocument(definitions)
  return {
    kind = 'document',
    definitions = definitions
  }
end

local function cFragmentDefinition(name, typeCondition, selectionSet)
  return {
    kind = 'fragmentDefinition',
    name = name,
    typeCondition = typeCondition,
    selectionSet = selectionSet
  }
end

local function cNamedType(name)
  return {
    kind = 'namedType',
    name = name
  }
end

local function cListType(type)
  return {
    kind = 'listType',
    type = type
  }
end

local function cNonNullType(type)
  return {
    kind = 'nonNullType',
    type = type
  }
end

local function cInlineFragment(...)
  local args = pack(...)
  local result = { kind = 'inlineFragment' }
  result.selectionSet = args[#args]
  for i = 1, #args - 1 do
    if args[i].kind == 'namedType' or args[i].kind == 'listType' or args[i].kind == 'nonNullType' then
      result.typeCondition = args[i]
    elseif args[i][1] and args[i][1].kind == 'directive' then
      result.directives = args[i]
    end
  end
  return result
end

local function cVariable(name)
  return {
    kind = 'variable',
    name = name
  }
end

local function cVariableDefinition(variable, type, defaultValue)
  return {
    kind = 'variableDefinition',
    variable = variable,
    type = type,
    defaultValue = defaultValue
  }
end

local function cDirective(name, arguments)
  return {
    kind = 'directive',
    name = name,
    arguments = arguments
  }
end

-- Simple types
local rawName = (P'_' + R('az', 'AZ')) * (P'_' + R'09' + R('az', 'AZ')) ^ 0
local name = rawName / cName
local fragmentName = (rawName - ('on' * -rawName)) / cName
local alias = ws * name * P':' * ws / cAlias

local integerPart = P'-' ^ -1 * ('0' + R'19' * R'09' ^ 0)
local intValue = integerPart / cInt
local fractionalPart = '.' * R'09' ^ 1
local exponentialPart = S'Ee' * S'+-' ^ -1 * R'09' ^ 1
local floatValue = integerPart * ((fractionalPart * exponentialPart) + fractionalPart + exponentialPart) / cFloat

local booleanValue = (P'true' + P'false') / cBoolean
local stringValue = P'"' * C((P'\\"' + 1 - S'"\n') ^ 0) * P'"' / cString
local enumValue = (rawName - 'true' - 'false' - 'null') / cEnum
local variable = ws * '$' * name / cVariable

-- Grammar
local graphQL = P {
  'document',
  document = ws * list('definition') / cDocument * -1,
  definition = _'operation' + _'fragmentDefinition',

  operationType = C(P'query' + P'mutation'),
  operation = (_'operationType' * ws * maybe(name) * maybe('variableDefinitions') * maybe('directives') * _'selectionSet' + _'selectionSet') / cOperation,
  fragmentDefinition = 'fragment' * ws * fragmentName * ws * _'typeCondition' * ws * _'selectionSet' / cFragmentDefinition,

  selectionSet = ws * '{' * ws * list('selection') * ws * '}' / cSelectionSet,
  selection = ws * (_'field' + _'fragmentSpread' + _'inlineFragment'),

  field = ws * maybe(alias) * name * maybe('arguments') * maybe('directives') * maybe('selectionSet') / cField,
  fragmentSpread = ws * '...' * ws * fragmentName * maybe('directives') / cFragmentSpread,
  inlineFragment = ws * '...' * ws * maybe('typeCondition') * maybe('directives') * _'selectionSet' / cInlineFragment,
  typeCondition = 'on' * ws * _'namedType',

  argument = ws * name * ':' * _'value' / cArgument,
  arguments = '(' * list('argument', 1) * ')',

  directive = '@' * name * maybe('arguments') / cDirective,
  directives = ws * list('directive', 1) * ws,

  variableDefinition = ws * variable * ws * ':' * ws * _'type' * (ws * '=' * _'value') ^ -1 * comma * ws / cVariableDefinition,
  variableDefinitions = ws * '(' * list('variableDefinition', 1) * ')',

  value = ws * (variable + _'objectValue' + _'listValue' + enumValue + stringValue + booleanValue + floatValue + intValue),
  listValue = '[' * list('value') * ']' / cList,
  objectFieldValue = ws * C(rawName) * ws * ':' * ws * _'value' * comma / cObjectField,
  objectValue = '{' * ws * list('objectFieldValue') * ws * '}' / cObject,

  type = _'nonNullType' + _'listType' + _'namedType',
  namedType = name / cNamedType,
  listType = '[' * ws * _'type' * ws * ']' / cListType,
  nonNullType = (_'namedType' + _'listType') * '!' / cNonNullType
}

-- TODO doesn't handle quotes that immediately follow escaped backslashes.
local function stripComments(str)
  return (str .. '\n'):gsub('(.-\n)', function(line)
    local index = 1
    while line:find('#', index) do
      local pos = line:find('#', index) - 1
      local chunk = line:sub(1, pos)
      local _, quotes = chunk:gsub('([^\\]")', '')
      if quotes % 2 == 0 then
        return chunk .. '\n'
      else
        index = pos + 2
      end
    end

    return line
  end):sub(1, -2)
end

return function(str)
  assert(type(str) == 'string', 'parser expects a string')
  str = stripComments(str)
  line, lastLinePos = 1, 1
  return graphQL:match(str) or error('Syntax error near line ' .. line, 2)
end
