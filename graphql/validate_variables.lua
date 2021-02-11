local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')
local check = util.check

-- Traverse type more or less likewise util.coerceValue do.
local function checkVariableValue(variableName, value, variableType)
  check(variableName, 'variableName', 'string')
  check(variableType, 'variableType', 'table')

  local isNonNull = variableType.__type == 'NonNull'

  if isNonNull then
    variableType = types.nullable(variableType)
    if value == nil then
      error(('Variable "%s" expected to be non-null'):format(variableName))
    end
  end

  local isList = variableType.__type == 'List'
  local isScalar = variableType.__type == 'Scalar'
  local isInputObject = variableType.__type == 'InputObject'
  local isEnum = variableType.__type == 'Enum'

  -- Nullable variable type + null value case: value can be nil only when
  -- isNonNull is false.
  if value == nil then return end

  if isList then
    if type(value) ~= 'table' then
      error(('Variable "%s" for a List must be a Lua ' ..
        'table, got %s'):format(variableName, type(value)))
    end
    if not util.is_array(value) then
      error(('Variable "%s" for a List must be an array, ' ..
        'got map'):format(variableName))
    end
    assert(variableType.ofType ~= nil, 'variableType.ofType must not be nil')
    for i, item in ipairs(value) do
      local itemName = variableName .. '[' .. tostring(i) .. ']'
      checkVariableValue(itemName, item, variableType.ofType)
    end
    return
  end

  if isInputObject then
    if type(value) ~= 'table' then
      error(('Variable "%s" for the InputObject "%s" must ' ..
        'be a Lua table, got %s'):format(variableName, variableType.name,
        type(value)))
    end

    -- check all fields: as from value as well as from schema
    local fieldNameSet = {}
    for fieldName, _ in pairs(value) do
        fieldNameSet[fieldName] = true
    end
    for fieldName, _ in pairs(variableType.fields) do
        fieldNameSet[fieldName] = true
    end

    for fieldName, _ in pairs(fieldNameSet) do
      local fieldValue = value[fieldName]
      if type(fieldName) ~= 'string' then
        error(('Field key of the variable "%s" for the ' ..
          'InputObject "%s" must be a string, got %s'):format(variableName,
          variableType.name, type(fieldName)))
      end
      if type(variableType.fields[fieldName]) == 'nil' then
        error(('Unknown field "%s" of the variable "%s" ' ..
          'for the InputObject "%s"'):format(fieldName, variableName,
          variableType.name))
      end

      local childType = variableType.fields[fieldName].kind
      local childName = variableName .. '.' .. fieldName
      checkVariableValue(childName, fieldValue, childType)
    end

    return
  end

  if isEnum then
      for _, item in pairs(variableType.values) do
        if util.cmpdeeply(item.value, value) then
          return
        end
      end
      error(('Wrong variable "%s" for the Enum "%s" with value %s'):format(
        variableName, variableType.name, value))
  end

  if isScalar then
    check(variableType.isValueOfTheType, 'isValueOfTheType', 'function')
    if not variableType.isValueOfTheType(value) then
      error(('Wrong variable "%s" for the Scalar "%s"'):format(
        variableName, variableType.name))
    end
    return
  end

  error(('Unknown type of the variable "%s"'):format(variableName))
end

local function validate_variables(context)
  -- check that all variable values have corresponding variable declaration
  for variableName, _ in pairs(context.variables or {}) do
    if context.variableTypes[variableName] == nil then
      error(('There is no declaration for the variable "%s"')
        :format(variableName))
    end
  end

  -- check that variable values have correct type
  for variableName, variableType in pairs(context.variableTypes) do
    local value = (context.variables or {})[variableName]
    checkVariableValue(variableName, value, variableType)
  end
end

return {
    validate_variables = validate_variables,
}
