local path = (...):gsub('%.[^%.]+$', '')
local util = require(path .. '.util')
local ffi = require('ffi')
local format = string.format

local function error(...)
  return _G.error(..., 0)
end

local types = {}

local registered_types = {}
local global_schema = '__global__'
function types.get_env(schema_name)
    if schema_name == nil then
        schema_name = global_schema
    end

    registered_types[schema_name] = registered_types[schema_name] or {}
    return registered_types[schema_name]
end

local function initFields(kind, fields)
  assert(type(fields) == 'table', 'fields table must be provided')

  local result = {}

  for fieldName, field in pairs(fields) do
    field = field.__type and { kind = field } or field
    result[fieldName] = {
      name = fieldName,
      kind = field.kind,
      description = field.description,
      deprecationReason = field.deprecationReason,
      arguments = field.arguments or {},
      resolve = kind == 'Object' and field.resolve or nil,
    }
  end

  return result
end

function types.nonNull(kind)
  assert(kind, 'Must provide a type')

  return {
    __type = 'NonNull',
    ofType = kind,
  }
end

function types.list(kind)
  assert(kind, 'Must provide a type')

  local instance = {
    __type = 'List',
    ofType = kind,
  }

  instance.nonNull = types.nonNull(instance)

  return instance
end

function types.nullable(kind)
    assert(type(kind) == 'table', 'kind must be a table, got ' .. type(kind))

    if kind.__type ~= 'NonNull' then return kind end

    assert(kind.ofType ~= nil, 'kind.ofType must not be nil')
    return types.nullable(kind.ofType)
end

function types.bare(kind)
    assert(type(kind) == 'table', 'kind must be a table, got ' .. type(kind))

    if kind.ofType == nil then return kind end

    assert(kind.ofType ~= nil, 'kind.ofType must not be nil')
    return types.bare(kind.ofType)
end

function types.scalar(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  assert(type(config.serialize) == 'function', 'serialize must be a function')
  assert(type(config.isValueOfTheType) == 'function', 'isValueOfTheType must be a function')
  assert(type(config.parseLiteral) == 'function', 'parseLiteral must be a function')
  if config.parseValue then
    assert(type(config.parseValue) == 'function', 'parseValue must be a function')
  end

  local instance = {
    __type = 'Scalar',
    name = config.name,
    description = config.description,
    serialize = config.serialize,
    parseValue = config.parseValue,
    parseLiteral = config.parseLiteral,
    isValueOfTheType = config.isValueOfTheType,
    specifiedByUrl = config.specifiedByUrl,
  }

  instance.nonNull = types.nonNull(instance)

  return instance
end

function types.object(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  if config.isTypeOf then
    assert(type(config.isTypeOf) == 'function', 'must provide isTypeOf as a function')
  end

  local fields
  if type(config.fields) == 'function' then
    fields = util.compose(util.bind1(initFields, 'Object'), config.fields)
  else
    fields = initFields('Object', config.fields)
  end

  local instance = {
    __type = 'Object',
    name = config.name,
    description = config.description,
    isTypeOf = config.isTypeOf,
    fields = fields,
    interfaces = config.interfaces,
  }

  instance.nonNull = types.nonNull(instance)

  types.get_env(config.schema)[config.name] = instance

  return instance
end

function types.interface(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  assert(type(config.fields) == 'table', 'fields table must be provided')
  if config.resolveType then
    assert(type(config.resolveType) == 'function', 'must provide resolveType as a function')
  end

  local fields
  if type(config.fields) == 'function' then
    fields = util.compose(util.bind1(initFields, 'Interface'), config.fields)
  else
    fields = initFields('Interface', config.fields)
  end

  local instance = {
    __type = 'Interface',
    name = config.name,
    description = config.description,
    fields = fields,
    resolveType = config.resolveType,
  }

  instance.nonNull = types.nonNull(instance)

  types.get_env(config.schema)[config.name] = instance

  return instance
end

function types.enum(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  assert(type(config.values) == 'table', 'values table must be provided')

  local instance
  local values = {}

  for name, entry in pairs(config.values) do
    entry = type(entry) == 'table' and entry or { value = entry }

    values[name] = {
      name = name,
      description = entry.description,
      deprecationReason = entry.deprecationReason,
      value = entry.value,
    }
  end

  instance = {
    __type = 'Enum',
    name = config.name,
    description = config.description,
    values = values,
    serialize = function(name)
      return instance.values[name] and instance.values[name].value or name
    end,
  }

  instance.nonNull = types.nonNull(instance)

  types.get_env(config.schema)[config.name] = instance

  return instance
end

function types.union(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  assert(type(config.types) == 'table', 'types table must be provided')

  local instance = {
    __type = 'Union',
    name = config.name,
    types = config.types,
  }

  instance.nonNull = types.nonNull(instance)

  types.get_env(config.schema)[config.name] = instance

  return instance
end

function types.inputObject(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')

  local fields = {}
  for fieldName, field in pairs(config.fields) do
    field = field.__type and { kind = field } or field
    fields[fieldName] = {
      name = fieldName,
      kind = field.kind,
    }
  end

  local instance = {
    __type = 'InputObject',
    name = config.name,
    description = config.description,
    fields = fields,
  }

  types.get_env(config.schema)[config.name] = instance

  return instance
end

-- Based on the code from tarantool/checks.
local function isInt(value)
  if type(value) == 'number' then
    return value >= -2^31 and value < 2^31 and math.floor(value) == value
  end

  if type(value) == 'cdata' then
    if ffi.istype('int64_t', value) then
      return value >= -2^31 and value < 2^31
    elseif ffi.istype('uint64_t', value) then
      return value < 2^31
    end
  end

  return false
end

local function coerceInt(value)
  if value ~= nil then
    value = tonumber(value)
    if not isInt(value) then return end
  end

  return value
end

types.int = types.scalar({
  name = 'Int',
  description = "The `Int` scalar type represents non-fractional signed whole numeric values. " ..
                "Int can represent values from -(2^31) to 2^31 - 1, inclusive.",
  serialize = coerceInt,
  parseLiteral = function(node)
    return coerceInt(node.value)
  end,
  isValueOfTheType = isInt,
})

-- The code from tarantool/checks.
local function isLong(value)
  if type(value) == 'number' then
    -- Double floating point format has 52 fraction bits. If we want to keep
    -- integer precision, the number must be less than 2^53.
    return value > -2^53 and value < 2^53 and math.floor(value) == value
  end

  if type(value) == 'cdata' then
    if ffi.istype('int64_t', value) then
      return true
    elseif ffi.istype('uint64_t', value) then
      return value < 2^63
    end
  end

  return false
end

local function coerceLong(value)
  if value ~= nil then
    value = tonumber64(value)
    if not isLong(value) then return end
  end

  return value
end

types.long = types.scalar({
  name = 'Long',
  description = "The `Long` scalar type represents non-fractional signed whole numeric values. " ..
          "Long can represent values from -(2^52) to 2^52 - 1, inclusive.",
  serialize = coerceLong,
  parseLiteral = function(node)
    return coerceLong(node.value)
  end,
  isValueOfTheType = isLong,
})

local function isFloat(value)
  return type(value) == 'number'
end

local function coerceFloat(value)
  if value ~= nil then
    value = tonumber(value)
    if not isFloat(value) then return end
  end

  return value
end

types.float = types.scalar({
  name = 'Float',
  serialize = coerceFloat,
  parseLiteral = function(node)
    return coerceFloat(node.value)
  end,
  isValueOfTheType = isFloat,
})

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

types.string = types.scalar({
  name = 'String',
  description = "The `String` scalar type represents textual data, represented as UTF-8 character sequences. " ..
          "The String type is most often used by GraphQL to represent free-form human-readable text.",
  serialize = coerceString,
  parseLiteral = function(node)
    return coerceString(node.value)
  end,
  isValueOfTheType = isString,
})

local function toboolean(x)
  return (x and x ~= 'false') and true or false
end

local function isBoolean(value)
  return type(value) == 'boolean'
end

local function coerceBoolean(value)
  if value ~= nil then
    value = toboolean(value)
    if not isBoolean(value) then return end
  end

  return value
end

types.boolean = types.scalar({
  name = 'Boolean',
  description = "The `Boolean` scalar type represents `true` or `false`.",
  serialize = coerceBoolean,
  parseLiteral = function(node)
    if node.kind ~= 'boolean' then
      error(('Could not coerce value "%s" with type "%s" to type boolean'):format(node.value, node.kind))
    end
    return coerceBoolean(node.value)
  end,
  isValueOfTheType = isBoolean,
})

--[[
The ID scalar type represents a unique identifier,
often used to refetch an object or as the key for a cache.
The ID type is serialized in the same way as a String;
however, defining it as an ID signifies that it is not intended to be human‐readable.
--]]
types.id = types.scalar({
  name = 'ID',
  serialize = coerceString,
  parseLiteral = function(node)
    return coerceString(node.value)
  end,
  isValueOfTheType = isString,
})

function types.directive(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')

  local instance = {
    __type = 'Directive',
    name = config.name,
    description = config.description,
    arguments = config.arguments,
    onQuery = config.onQuery,
    onMutation = config.onMutation,
    onField = config.onField,
    onFragmentDefinition = config.onFragmentDefinition,
    onFragmentSpread = config.onFragmentSpread,
    onInlineFragment = config.onInlineFragment,
    onVariableDefinition = config.onVariableDefinition,
    onSchema = config.onSchema,
    onScalar = config.onScalar,
    onObject = config.onObject,
    onFieldDefinition = config.onFieldDefinition,
    onArgumentDefinition = config.onArgumentDefinition,
    onInterface = config.onInterface,
    onUnion = config.onUnion,
    onEnum = config.onEnum,
    onEnumValue = config.onEnumValue,
    onInputObject = config.onInputObject,
    onInputFieldDefinition = config.onInputFieldDefinition,
    isRepeatable = config.isRepeatable or false,
  }

  return instance
end

types.include = types.directive({
  name = 'include',
  description = 'Directs the executor to include this field or fragment only when the `if` argument is true.',
  arguments = {
    ['if'] = { kind = types.boolean.nonNull, description = 'Included when true.'},
  },
  onField = true,
  onFragmentSpread = true,
  onInlineFragment = true,
})

types.skip = types.directive({
  name = 'skip',
  description = 'Directs the executor to skip this field or fragment when the `if` argument is true.',
  arguments = {
    ['if'] = { kind = types.boolean.nonNull, description = 'Skipped when true.' },
  },
  onField = true,
  onFragmentSpread = true,
  onInlineFragment = true,
})

types.specifiedBy = types.directive({
  name = 'specifiedBy',
  description = 'Custom scalar specification.',
  arguments = {
    ['url'] = { kind = types.string.nonNull, description = 'Scalar specification URL.', }
  },
  onScalar = true,
})

types.resolve = function(type_name_or_obj, schema)
    if type(type_name_or_obj) == 'table' then
        return type_name_or_obj
    end

    if type(type_name_or_obj) ~= 'string' then
        error('types.resolve() expects type to be string or table')
    end

    local type_obj = types.get_env(schema)[type_name_or_obj]

    if type_obj == nil then
        error(format("No type found named '%s'", type_name_or_obj))
    end

    return type_obj
end

return types
