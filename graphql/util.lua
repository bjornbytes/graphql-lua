local ffi = require('ffi')
local yaml = require('yaml').new({encode_use_tostring = true})

local function error(...)
  return _G.error(..., 0)
end

local function map(t, fn)
  local res = {}
  for k, v in pairs(t) do res[k] = fn(v, k) end
  return res
end

local function find(t, fn)
  for k, v in pairs(t) do
    if fn(v, k) then return v end
  end
end

local function filter(t, fn)
  local res = {}
  for _,v in pairs(t) do
    if fn(v) then
      table.insert(res, v)
    end
  end
  return res
end

local function values(t)
  local res = {}
  for _, value in pairs(t) do
    table.insert(res, value)
  end
  return res
end

local function compose(f, g)
  return function(...) return f(g(...)) end
end

local function bind1(func, x)
  return function(y)
    return func(x, y)
  end
end

local function trim(s)
  return s:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s%s+', ' ')
end

local function getTypeName(t)
  if t.name ~= nil then
    return t.name
  elseif t.__type == 'NonNull' then
    return ('NonNull(%s)'):format(getTypeName(t.ofType))
  elseif t.__type == 'List' then
    return ('List(%s)'):format(getTypeName(t.ofType))
  end

  local err = ('Internal error: unknown type:\n%s'):format(yaml.encode(t))
  error(err)
end

local function coerceValue(node, schemaType, variables, opts)
  variables = variables or {}
  opts = opts or {}
  local strict_non_null = opts.strict_non_null or false

  if schemaType.__type == 'NonNull' then
    local res = coerceValue(node, schemaType.ofType, variables, opts)
    if strict_non_null and res == nil then
      error(('Expected non-null for "%s", got null'):format(
        getTypeName(schemaType)))
    end
    return res
  end

  if not node then
    return nil
  end

  -- handle precompiled values
  if node.compiled ~= nil then
    return node.compiled
  end

  if node.kind == 'variable' then
    return variables[node.name.value]
  end

  if schemaType.__type == 'List' then
    if node.kind ~= 'list' then
      error('Expected a list')
    end

    return map(node.values, function(value)
      return coerceValue(value, schemaType.ofType, variables, opts)
    end)
  end

  local isInputObject = schemaType.__type == 'InputObject'
  if isInputObject then
    if node.kind ~= 'inputObject' then
      error('Expected an input object')
    end

    -- check all fields: as from value as well as from schema
    local fieldNameSet = {}
    local fieldValues = {}
    for _, field in ipairs(node.values) do
        fieldNameSet[field.name] = true
        fieldValues[field.name] = field.value
    end
    for fieldName, _ in pairs(schemaType.fields) do
        fieldNameSet[fieldName] = true
    end

    local inputObjectValue = {}
    for fieldName, _ in pairs(fieldNameSet) do
      if not schemaType.fields[fieldName] then
        error(('Unknown input object field "%s"'):format(fieldName))
      end

      local childValue = fieldValues[fieldName]
      local childType = schemaType.fields[fieldName].kind
      inputObjectValue[fieldName] = coerceValue(childValue, childType,
        variables, opts)
    end

    return inputObjectValue
  end

  if schemaType.__type == 'Enum' then
    if node.kind ~= 'enum' then
      error(('Expected enum value, got %s'):format(node.kind))
    end

    if not schemaType.values[node.value] then
      error(('Invalid enum value "%s"'):format(node.value))
    end

    return node.value
  end

  if schemaType.__type == 'Scalar' then
    if schemaType.parseLiteral(node) == nil then
      error(('Could not coerce "%s" to "%s"'):format(
        node.value or node.kind, schemaType.name))
    end

    return schemaType.parseLiteral(node)
  end
end

--- Check whether passed value has one of listed types.
---
--- @param obj value to check
---
--- @tparam string obj_name name of the value to form an error
---
--- @tparam string type_1
--- @tparam[opt] string type_2
--- @tparam[opt] string type_3
---
--- @return nothing
local function check(obj, obj_name, type_1, type_2, type_3)
    if type(obj) == type_1 or type(obj) == type_2 or type(obj) == type_3 then
        return
    end

    if type_3 ~= nil then
        error(('%s must be a %s or a % or a %s, got %s'):format(obj_name,
            type_1, type_2, type_3, type(obj)))
    elseif type_2 ~= nil then
        error(('%s must be a %s or a %s, got %s'):format(obj_name, type_1,
            type_2, type(obj)))
    else
        error(('%s must be a %s, got %s'):format(obj_name, type_1, type(obj)))
    end
end

--- Check whether table is an array.
---
--- Based on [that][1] implementation.
--- [1]: https://github.com/mpx/lua-cjson/blob/db122676/lua/cjson/util.lua
---
--- @tparam table table to check
--- @return[1] `true` if passed table is an array (includes the empty table
--- case)
--- @return[2] `false` otherwise
local function is_array(table)
    if type(table) ~= 'table' then
        return false
    end

    local max = 0
    local count = 0
    for k, _ in pairs(table) do
        if type(k) == 'number' then
            if k > max then
                max = k
            end
            count = count + 1
        else
            return false
        end
    end
    if max > count * 2 then
        return false
    end

    return max >= 0
end

-- Copied from tarantool/tap
local function cmpdeeply(got, expected)
    if type(expected) == "number" or type(got) == "number" then
        if got ~= got and expected ~= expected then
            return true -- nan
        end
        return got == expected
    end

    if ffi.istype('bool', got) then got = (got == 1) end
    if ffi.istype('bool', expected) then expected = (expected == 1) end

    if type(got) ~= type(expected) then
        return false
    end

    if type(got) ~= 'table' or type(expected) ~= 'table' then
        return got == expected
    end

    local visited_keys = {}

    for i, v in pairs(got) do
        visited_keys[i] = true
        if not cmpdeeply(v, expected[i]) then
            return false
        end
    end

    -- check if expected contains more keys then got
    for i in pairs(expected) do
        if visited_keys[i] ~= true then
            return false
        end
    end

    return true
end

return {
  map = map,
  find = find,
  filter = filter,
  values = values,
  compose = compose,
  bind1 = bind1,
  trim = trim,
  getTypeName = getTypeName,
  coerceValue = coerceValue,

  is_array = is_array,
  check = check,
  cmpdeeply = cmpdeeply,
}
