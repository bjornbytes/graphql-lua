local lpeg = require 'lpeg'
local P, R, S, V, C, Ct, Cmt, Cg, Cc, Cf = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Ct, lpeg.Cmt, lpeg.Cg, lpeg.Cc, lpeg.Cf

local function pack(...)
  return { n = select('#', ...), ... }
end

-- Utility
local space = S(' \t\r\n') ^ 0
local comma = P(',') ^ 0

local function cName(name)
  if #name == 0 then return nil end

  return {
    kind = 'name',
    value = name
  }
end

local function cInt(value)
  return {
    kind = 'int',
    value = value
  }
end

local function cFloat(value)
  return {
    kind = 'float',
    value = value
  }
end

local function cBoolean(value)
  return {
    kind = 'boolean',
    value = value
  }
end

local function cString(value)
  return {
    kind = 'string',
    value = value
  }
end

local function cEnum(value)
  return {
    kind = 'enum',
    value = value
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

local function cFragmentSpread(name)
  return {
    kind = 'fragmentSpread',
    name = name
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
  if #args == 2 then
    return {
      kind = 'inlineFragment',
      typeCondition = args[1],
      selectionSet = args[2]
    }
  elseif #args == 1 then
    return {
      kind = 'inlineFragment',
      selectionSet = args[1]
    }
  end
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

-- "Terminals"
local rawName = R('az', 'AZ') * (P('_') + R('09') + R('az', 'AZ')) ^ 0
local name = rawName / cName
local alias = space * name * P(':') * space / cAlias
local integerPart = P('-') ^ -1 * (P('0') + R('19') * R('09') ^ 0)
local intValue = integerPart / cInt
local fractionalPart = P('.') * R('09') ^ 1
local exponentialPart = S('Ee') * S('+-') ^ -1 * R('09') ^ 1
local floatValue = integerPart * (fractionalPart + exponentialPart + (fractionalPart * exponentialPart)) / cFloat
local booleanValue = (P('true') + P('false')) / cBoolean
local stringValue = P('"') * C((P('\\"') + 1 - S('"\n')) ^ 0) * P('"') / cString
local enumValue = (rawName - 'true' - 'false' - 'null') / cEnum
local fragmentName = (rawName - 'on') / cName
local fragmentSpread = space * P('...') * fragmentName / cFragmentSpread
local operationType = C(P('query') + P('mutation'))
local variable = space * P('$') * name / cVariable

-- Nonterminals
local graphQL = P {
  'document',
  document = space * Ct((V('definition') * comma * space) ^ 0) / cDocument * -1,
  definition = V('operation') + V('fragmentDefinition'),
  operation = (operationType * space * name ^ -1 * V('variableDefinitions') ^ -1 * V('directives') ^ -1 * V('selectionSet') + V('selectionSet')) / cOperation,
  fragmentDefinition = P('fragment') * space * fragmentName * space * V('typeCondition') * space * V('selectionSet') / cFragmentDefinition,
  inlineFragment = P('...') * space * V('typeCondition') ^ -1 * V('selectionSet') / cInlineFragment,
  selectionSet = space * P('{') * space * Ct(V('selection') ^ 0) * space * P('}') / cSelectionSet,
  selection = space * (V('field') + fragmentSpread + V('inlineFragment')),
  field = space * alias ^ -1 * name * V('arguments') ^ -1 * V('directives') ^ -1 * V('selectionSet') ^ -1 * comma / cField,
  argument = space * name * P(':') * V('value') * comma / cArgument,
  arguments = P('(') * Ct(V('argument') ^ 1) * P(')'),
  value = space * (variable + V('objectValue') + V('listValue') + enumValue + stringValue + booleanValue + floatValue + intValue),
  listValue = P('[') * Ct((V('value') * comma) ^ 0) * P(']') / cList,
  objectFieldValue = space * C(rawName) * space * P(':') * space * V('value') * comma / cObjectField,
  objectValue = P('{') * space * Ct(V('objectFieldValue') ^ 0) * space * P('}') / cObject,
  type = V('nonNullType') + V('listType') + V('namedType'),
  namedType = name / cNamedType,
  listType = P('[') * space * V('type') * space * P(']') / cListType,
  nonNullType = (V('namedType') + V('listType')) * P('!') / cNonNullType,
  typeCondition = P('on') * space * V('namedType'),
  variableDefinition = space * variable * space * P(':') * space * V('type') * (space * P('=') * V('value')) ^ -1 * comma * space / cVariableDefinition,
  variableDefinitions = P('(') * Ct(V('variableDefinition') ^ 1) * P(')'),
  directive = P('@') * name * V('arguments') ^ -1 / cDirective,
  directives = space * Ct((V('directive') * comma * space) ^ 1) * space
}

return function(str)
  assert(type(str) == 'string', 'parser expects a string')
  return graphQL:match(str)
end
