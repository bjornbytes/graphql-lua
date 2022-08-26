local types = require('graphql.types')
local util = require('graphql.util')
local check = util.check

local function error(...)
  return _G.error(..., 0)
end

-- Traverse type more or less likewise util.coerceValue do.
local function checkVariableValue(variableName, value, variableType, isNonNullDefaultDefined)
  check(variableName, 'variableName', 'string')
  check(variableType, 'variableType', 'table')

  local isNonNull = variableType.__type == 'NonNull'
  isNonNullDefaultDefined = isNonNullDefaultDefined or false

  if isNonNull then
    variableType = types.nullable(variableType)
    if (type(value) == 'cdata' and value == nil) or
       (type(value) == 'nil' and not isNonNullDefaultDefined) then
      error(('Variable %q expected to be non-null'):format(variableName))
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
      error(('Variable %q for a List must be a Lua ' ..
        'table, got %s'):format(variableName, type(value)))
    end
    if not util.is_array(value) then
      error(('Variable %q for a List must be an array, ' ..
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
      error(('Variable %q for the InputObject %q must ' ..
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
        error(('Field key of the variable %q for the ' ..
          'InputObject %q must be a string, got %s'):format(variableName,
          variableType.name, type(fieldName)))
      end
      if type(variableType.fields[fieldName]) == 'nil' then
        error(('Unknown field %q of the variable %q ' ..
          'for the InputObject %q'):format(fieldName, variableName,
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
      error(('Wrong variable %q for the Enum "%s" with value %q'):format(
        variableName, variableType.name, value))
  end

  if isScalar then
    check(variableType.isValueOfTheType, 'isValueOfTheType', 'function')
    if not variableType.isValueOfTheType(value) then
      error(('Wrong variable %q for the Scalar %q'):format(
        variableName, variableType.name))
    end
    return
  end

  error(('Unknown type of the variable %q'):format(variableName))
end

local function validate_variables(context)
  -- check that all variable values have corresponding variable declaration
  for variableName, _ in pairs(context.variables or {}) do
    if context.variableTypes[variableName] == nil then
      error(('There is no declaration for the variable %q')
        :format(variableName))
    end
  end

  -- check that variable values have correct type
  for variableName, variableType in pairs(context.variableTypes) do
    -- Check if default value presents.
    local isNonNullDefaultDefined = false
    for _, variableDefinition in ipairs(context.operation.variableDefinitions) do
      if variableDefinition.variable.name.value == variableName and
         variableDefinition.defaultValue ~= nil then
        if (variableDefinition.defaultValue.value ~= nil) or (variableDefinition.defaultValue.values ~= nil) then
          isNonNullDefaultDefined = true
        end
      end
    end

    local value = (context.variables or {})[variableName]
    checkVariableValue(variableName, value, variableType, isNonNullDefaultDefined)
  end
end

return {
    validate_variables = validate_variables,
}
