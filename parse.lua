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
    kind = 'object',
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
    if not key and tokens[i][1].kind == 'argument' then
      key = 'arguments'
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

    if #args >= 3 then
      result.name, result.selectionSet = unpack(args, 2, 3)
    else
      result.selectionSet = args[2]
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

local function cType(name)
  return {
    kind = 'type',
    name = name
  }
end

-- "Terminals"
local rawName = space * R('az', 'AZ') * (P('_') + R('09') + R('az', 'AZ')) ^ 0
local name = rawName / cName
local alias = space * name * P(':') / cAlias
local integerPart = P('-') ^ -1 * (P('0') + R('19') * R('09') ^ 0)
local intValue = integerPart / cInt
local fractionalPart = P('.') * R('09') ^ 1
local exponentialPart = S('Ee') * S('+-') ^ -1 * R('09') ^ 1
local floatValue = integerPart * (fractionalPart ^ -1 * exponentialPart ^ -1) / cFloat
local booleanValue = (P('true') + P('false')) / cBoolean
local stringValue = P('"') * C((P('\\"') + 1 - S('"\n')) ^ 0) * P('"') / cString
local enumValue = (rawName - 'true' - 'false' - 'null') / cEnum
local typeCondition = P('on') * space * name / cType
local fragmentName = (rawName - 'on') / cName
local fragmentSpread = space * P('...') * fragmentName / cFragmentSpread
local operationType = C(P('query') + P('mutation'))

-- Nonterminals
local graphQL = P {
  'document',
  document = space * Ct((V('definition') * comma * space) ^ 0) / cDocument * -1,
  definition = V('operation') + V('fragmentDefinition'),
  operation = (operationType * space * name ^ -1 * V('selectionSet') + V('selectionSet')) / cOperation,
  fragmentDefinition = P('fragment') * space * fragmentName * space * typeCondition * space * V('selectionSet') / cFragmentDefinition,
  selectionSet = space * P('{') * space * Ct(V('selection') ^ 0) * space * P('}') / cSelectionSet,
  selection = space * (V('field') + fragmentSpread),
  field = space * alias ^ -1 * name * V('arguments') ^ -1 * V('selectionSet') ^ -1 * comma / cField,
  argument = space * name * P(':') * V('value') * comma / cArgument,
  arguments = P('(') * Ct(V('argument') ^ 1) * P(')'),
  value = space * (V('objectValue') + V('listValue') + enumValue + stringValue + booleanValue + floatValue + intValue),
  listValue = P('[') * Ct((V('value') * comma) ^ 0) * P(']') / cList,
  objectFieldValue = C(rawName) * space * P(':') * space * V('value') * comma / cObjectField,
  objectValue = P('{') * space * Ct(V('objectFieldValue') ^ 0) * space * P('}') / cObject
}

return function(str)
  return graphQL:match(str)
end
