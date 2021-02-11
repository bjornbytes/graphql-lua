local path = (...):gsub('%.[^%.]+$', '')
local util = require(path .. '.util')
local ffi = require('ffi')
local format = string.format

local registered_types = {}
local types = {}

local function get_env()
    return registered_types
end

local function error(...)
  return _G.error(..., 0)
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
      resolve = kind == 'Object' and field.resolve or nil
    }
  end

  return result
end

function types.nonNull(kind)
  assert(kind, 'Must provide a type')

  return {
    __type = 'NonNull',
    ofType = kind
  }
end

function types.list(kind)
  assert(kind, 'Must provide a type')

  local instance = {
    __type = 'List',
    ofType = kind
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
  if config.parseValue or config.parseLiteral then
    assert(
      type(config.parseValue) == 'function' and type(config.parseLiteral) == 'function',
      'must provide both parseValue and parseLiteral to scalar type'
    )
  end

  local instance = {
    __type = 'Scalar',
    name = config.name,
    description = config.description,
    serialize = config.serialize,
    parseValue = config.parseValue,
    parseLiteral = config.parseLiteral,
    isValueOfTheType = config.isValueOfTheType,
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
    interfaces = config.interfaces
  }

  instance.nonNull = types.nonNull(instance)

  get_env()[config.name] = instance

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
    resolveType = config.resolveType
  }

  instance.nonNull = types.nonNull(instance)

  get_env()[config.name] = instance

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
      value = entry.value
    }
  end

  instance = {
    __type = 'Enum',
    name = config.name,
    description = config.description,
    values = values,
    serialize = function(name)
      return instance.values[name] and instance.values[name].value or name
    end
  }

  instance.nonNull = types.nonNull(instance)

  get_env()[config.name] = instance

  return instance
end

function types.union(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')
  assert(type(config.types) == 'table', 'types table must be provided')

  local instance = {
    __type = 'Union',
    name = config.name,
    types = config.types
  }

  instance.nonNull = types.nonNull(instance)

  get_env()[config.name] = instance

  return instance
end

function types.inputObject(config)
  assert(type(config.name) == 'string', 'type name must be provided as a string')

  local fields = {}
  for fieldName, field in pairs(config.fields) do
    field = field.__type and { kind = field } or field
    fields[fieldName] = {
      name = fieldName,
      kind = field.kind
    }
  end

  local instance = {
    __type = 'InputObject',
    name = config.name,
    description = config.description,
    fields = fields
  }

  get_env()[config.name] = instance

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

local function coerceInt(value)
  local value = tonumber(value)

  if value == nil then return end
  if not isInt(value) then return end

  return value
end

local function coerceLong(value)
  local value = tonumber64(value)

  if value == nil then return end
  if not isLong(value) then return end

  return value
end

types.int = types.scalar({
  name = 'Int',
  description = "The `Int` scalar type represents non-fractional signed whole numeric values. " ..
          "Int can represent values from -(2^31) to 2^31 - 1, inclusive.",
  serialize = coerceInt,
  parseValue = coerceInt,
  parseLiteral = function(node)
    if node.kind == 'int' then
      return coerceInt(node.value)
    end
  end,
  isValueOfTheType = isInt,
})

types.long = types.scalar({
  name = 'Long',
  description = "The `Long` scalar type represents non-fractional signed whole numeric values. " ..
          "Long can represent values from -(2^52) to 2^52 - 1, inclusive.",
  serialize = coerceLong,
  parseValue = coerceLong,
  parseLiteral = function(node)
    if node.kind == 'long' or node.kind == 'int' then
      return coerceLong(node.value)
    end
  end,
  isValueOfTheType = isLong,
})

types.float = types.scalar({
  name = 'Float',
  serialize = tonumber,
  parseValue = tonumber,
  parseLiteral = function(node)
    if node.kind == 'float' or node.kind == 'int' then
      return tonumber(node.value)
    end
  end,
  isValueOfTheType = function(value)
    return type(value) == 'number'
  end,
})

types.string = types.scalar({
  name = 'String',
  description = "The `String` scalar type represents textual data, represented as UTF-8 character sequences. " ..
          "The String type is most often used by GraphQL to represent free-form human-readable text.",
  serialize = tostring,
  parseValue = tostring,
  parseLiteral = function(node)
    if node.kind == 'string' then
      return node.value
    end
  end,
  isValueOfTheType = function(value)
    return type(value) == 'string'
  end,
})

local function toboolean(x)
  return (x and x ~= 'false') and true or false
end

types.boolean = types.scalar({
  name = 'Boolean',
  description = "The `Boolean` scalar type represents `true` or `false`.",
  serialize = toboolean,
  parseValue = toboolean,
  parseLiteral = function(node)
    if node.kind == 'boolean' then
      return toboolean(node.value)
    else
      return nil
    end
  end,
  isValueOfTheType = function(value)
    return type(value) == 'boolean'
  end,
})

types.id = types.scalar({
  name = 'ID',
  serialize = tostring,
  parseValue = tostring,
  parseLiteral = function(node)
    return node.kind == 'string' or node.kind == 'int' and node.value or nil
  end
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
    onInlineFragment = config.onInlineFragment
  }

  return instance
end

types.include = types.directive({
  name = 'include',
  description = 'Directs the executor to include this field or fragment only when the `if` argument is true.',
  arguments = {
    ['if'] = { kind = types.boolean.nonNull, description = 'Included when true.'}
  },
  onField = true,
  onFragmentSpread = true,
  onInlineFragment = true
})

types.skip = types.directive({
  name = 'skip',
  description = 'Directs the executor to skip this field or fragment when the `if` argument is true.',
  arguments = {
    ['if'] = { kind = types.boolean.nonNull, description = 'Skipped when true.' }
  },
  onField = true,
  onFragmentSpread = true,
  onInlineFragment = true
})

types.resolve = function(type_name_or_obj)
    if type(type_name_or_obj) == 'table' then
        return type_name_or_obj
    end

    if type(type_name_or_obj) ~= 'string' then
        error('types.resolve() expects type to be string or table')
    end

    local type_obj = registered_types[type_name_or_obj]

    if type_obj == nil then
        error(format("No type found named '%s'", type_name_or_obj))
    end

    return type_obj
end

return types
