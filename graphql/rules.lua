local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')
local introspection = require(path .. '.introspection')
local query_util = require(path .. '.query_util')

local function error(...)
  return _G.error(..., 0)
end

local function getParentField(context, name, count)
  if introspection.fieldMap[name] then return introspection.fieldMap[name] end

  count = count or 1
  local parent = context.objects[#context.objects - count]

  -- Unwrap lists and non-null types
  while parent.ofType do
    parent = parent.ofType
  end

  return parent.fields[name]
end

local rules = {}

function rules.uniqueOperationNames(node, context)
  local name = node.name and node.name.value

  if name then
    if context.operationNames[name] then
      error('Multiple operations exist named "' .. name .. '"')
    end

    context.operationNames[name] = true
  end
end

function rules.loneAnonymousOperation(node, context)
  local name = node.name and node.name.value

  if context.hasAnonymousOperation or (not name and next(context.operationNames)) then
    error('Cannot have more than one operation when using anonymous operations')
  end

  if not name then
    context.hasAnonymousOperation = true
  end
end

function rules.fieldsDefinedOnType(node, context)
  if context.objects[#context.objects] == false then
    local parent = context.objects[#context.objects - 1]
    while parent.ofType do parent = parent.ofType end
    error('Field "' .. node.name.value .. '" is not defined on type "' .. parent.name .. '"')
  end
end

function rules.argumentsDefinedOnType(node, context)
  if node.arguments then
    local parentField = getParentField(context, node.name.value)
    for _, argument in pairs(node.arguments) do
      local name = argument.name.value
      if not parentField.arguments[name] then
        error('Non-existent argument "' .. name .. '"')
      end
    end
  end
end

function rules.scalarFieldsAreLeaves(node, context)
  local field_t = types.bare(context.objects[#context.objects]).__type
  if field_t == 'Scalar' and node.selectionSet then
    local valueName = node.name.value
    error(('Scalar field %q cannot have subselections'):format(valueName))
  end
end

function rules.compositeFieldsAreNotLeaves(node, context)
  local field_t = types.bare(context.objects[#context.objects]).__type
  local isCompositeType = field_t == 'Object' or field_t == 'Interface' or
    field_t == 'Union'

  if isCompositeType and not node.selectionSet then
    local fieldName = node.name.value
    error(('Composite field %q must have subselections'):format(fieldName))
  end
end

function rules.unambiguousSelections(node, context)
  local selectionMap = {}
  local seen = {}

  local function findConflict(entryA, entryB)

    -- Parent types can't overlap if they're different objects.
    -- Interface and union types may overlap.
    if entryA.parent ~= entryB.parent and entryA.__type == 'Object' and entryB.__type == 'Object' then
      return
    end

    -- Error if there are aliases that map two different fields to the same name.
    if entryA.field.name.value ~= entryB.field.name.value then
      return 'Type name mismatch'
    end

    -- Error if there are fields with the same name that have different return types.
    if entryA.definition and entryB.definition and entryA.definition ~= entryB.definition then
      return 'Return type mismatch'
    end

    -- Error if arguments are not identical for two fields with the same name.
    local argsA = entryA.field.arguments or {}
    local argsB = entryB.field.arguments or {}

    if #argsA ~= #argsB then
      return 'Argument mismatch'
    end

    local argMap = {}

    for i = 1, #argsA do
      argMap[argsA[i].name.value] = argsA[i].value
    end

    for i = 1, #argsB do
      local name = argsB[i].name.value
      if not argMap[name] then
        return 'Argument mismatch'
      elseif argMap[name].kind ~= argsB[i].value.kind then
        return 'Argument mismatch'
      elseif argMap[name].value ~= argsB[i].value.value then
        return 'Argument mismatch'
      end
    end
  end

  local function validateField(key, entry)
    if selectionMap[key] then
      for i = 1, #selectionMap[key] do
        local conflict = findConflict(selectionMap[key][i], entry)
        if conflict then
          error(conflict)
        end
      end

      table.insert(selectionMap[key], entry)
    else
      selectionMap[key] = { entry }
    end
  end

  -- Recursively make sure that there are no ambiguous selections with the same name.
  local function validateSelectionSet(selectionSet, parentType)
    for _, selection in ipairs(selectionSet.selections) do
      if selection.kind == 'field' then
        if not parentType or not parentType.fields or not parentType.fields[selection.name.value] then return end

        local key = selection.alias and selection.alias.name.value or selection.name.value
        local definition = parentType.fields[selection.name.value].kind

        local fieldEntry = {
          parent = parentType,
          field = selection,
          definition = definition
        }

        validateField(key, fieldEntry)
      elseif selection.kind == 'inlineFragment' then
        local parentType = selection.typeCondition and context.schema:getType(
          selection.typeCondition.name.value) or parentType
        validateSelectionSet(selection.selectionSet, parentType)
      elseif selection.kind == 'fragmentSpread' then
        local fragmentDefinition = context.fragmentMap[selection.name.value]
        if fragmentDefinition and not seen[fragmentDefinition] then
          seen[fragmentDefinition] = true
          if fragmentDefinition and fragmentDefinition.typeCondition then
            local parentType = context.schema:getType(fragmentDefinition.typeCondition.name.value)
            validateSelectionSet(fragmentDefinition.selectionSet, parentType)
          end
        end
      end
    end
  end

  validateSelectionSet(node, context.objects[#context.objects])
end

function rules.uniqueArgumentNames(node, _)
  if node.arguments then
    local arguments = {}
    for _, argument in ipairs(node.arguments) do
      local name = argument.name.value
      if arguments[name] then
        error('Encountered multiple arguments named "' .. name .. '"')
      end
      arguments[name] = true
    end
  end
end

function rules.argumentsOfCorrectType(node, context)
  if node.arguments then
    local parentField = getParentField(context, node.name.value)
    for _, argument in pairs(node.arguments) do
      local name = argument.name.value
      local argumentType = parentField.arguments[name]
      util.coerceValue(argument.value, argumentType.kind or argumentType)
    end
  end
end

function rules.requiredArgumentsPresent(node, context)
  local arguments = node.arguments or {}
  local parentField = getParentField(context, node.name.value)
  for name, argument in pairs(parentField.arguments) do
    if argument.__type == 'NonNull' then
      local present = util.find(arguments, function(argument)
        return argument.name.value == name
      end)

      if not present then
        error('Required argument "' .. name .. '" was not supplied.')
      end
    end
  end
end

function rules.uniqueFragmentNames(node, _)
  local fragments = {}
  for _, definition in ipairs(node.definitions) do
    if definition.kind == 'fragmentDefinition' then
      local name = definition.name.value
      if fragments[name] then
        error('Encountered multiple fragments named "' .. name .. '"')
      end
      fragments[name] = true
    end
  end
end

function rules.fragmentHasValidType(node, context)
  if not node.typeCondition then return end

  local name = node.typeCondition.name.value
  local kind = context.schema:getType(name)

  if not kind then
    error('Fragment refers to non-existent type "' .. name .. '"')
  end

  if kind.__type ~= 'Object' and kind.__type ~= 'Interface' and kind.__type ~= 'Union' then
    error('Fragment type must be an Object, Interface, or Union, got ' .. kind.__type)
  end
end

function rules.noUnusedFragments(node, context)
  for _, definition in ipairs(node.definitions) do
    if definition.kind == 'fragmentDefinition' then
      local name = definition.name.value
      if not context.usedFragments[name] then
        error('Fragment "' .. name .. '" was not used.')
      end
    end
  end
end

function rules.fragmentSpreadTargetDefined(node, context)
  if not context.fragmentMap[node.name.value] then
    error('Fragment spread refers to non-existent fragment "' .. node.name.value .. '"')
  end
end

function rules.fragmentDefinitionHasNoCycles(node, context)
  local seen = { [node.name.value] = true }

  local function detectCycles(selectionSet)
    for _, selection in ipairs(selectionSet.selections) do
      if selection.kind == 'inlineFragment' then
        detectCycles(selection.selectionSet)
      elseif selection.kind == 'fragmentSpread' then
        if seen[selection.name.value] then
          error('Fragment definition has cycles')
        end

        seen[selection.name.value] = true

        local fragmentDefinition = context.fragmentMap[selection.name.value]
        if fragmentDefinition and fragmentDefinition.typeCondition then
          detectCycles(fragmentDefinition.selectionSet)
        end
      end
    end
  end

  detectCycles(node.selectionSet)
end

function rules.fragmentSpreadIsPossible(node, context)
  local fragment = node.kind == 'inlineFragment' and node or context.fragmentMap[node.name.value]

  local parentType = context.objects[#context.objects - 1]
  while parentType.ofType do parentType = parentType.ofType end

  local fragmentType
  if node.kind == 'inlineFragment' then
    fragmentType = node.typeCondition and context.schema:getType(node.typeCondition.name.value) or parentType
  else
    fragmentType = context.schema:getType(fragment.typeCondition.name.value)
  end

  -- Some types are not present in the schema.  Let other rules handle this.
  if not parentType or not fragmentType then return end

  local function getTypes(kind)
    if kind.__type == 'Object' then
      return { [kind] = kind }
    elseif kind.__type == 'Interface' then
      return context.schema:getImplementors(kind.name)
    elseif kind.__type == 'Union' then
      local types = {}
      for i = 1, #kind.types do
        types[kind.types[i]] = kind.types[i]
      end
      return types
    else
      return {}
    end
  end

  local parentTypes = getTypes(parentType)
  local fragmentTypes = getTypes(fragmentType)

  local valid = util.find(parentTypes, function(kind)
    local kind = kind
    -- Here is the check that type, mentioned in '... on some_type'
    -- conditional fragment expression is type of some field of parent object.
    -- In case of Union parent object and NonNull wrapped inner types
    -- graphql-lua missed unwrapping so we add it here
    while kind.__type == 'NonNull' do
      kind = kind.ofType
    end
    return fragmentTypes[kind]
  end)

  if not valid then
    error('Fragment type condition is not possible for given type')
  end
end

function rules.uniqueInputObjectFields(node, _)
  local function validateValue(value)
    if value.kind == 'listType' or value.kind == 'nonNullType' then
      return validateValue(value.type)
    elseif value.kind == 'inputObject' then
      local fieldMap = {}
      for _, field in ipairs(value.values) do
        if fieldMap[field.name] then
          error('Multiple input object fields named "' .. field.name .. '"')
        end

        fieldMap[field.name] = true

        validateValue(field.value)
      end
    end
  end

  if node.kind == 'inputObject' then
    validateValue(node)
  else
    validateValue(node.value)
  end
end

function rules.directivesAreDefined(node, context)
  if not node.directives then return end

  for _, directive in pairs(node.directives) do
    if not context.schema:getDirective(directive.name.value) then
      error('Unknown directive "' .. directive.name.value .. '"')
    end
  end
end

function rules.variablesHaveCorrectType(node, context)
  local function validateType(type)
    if type.kind == 'listType' or type.kind == 'nonNullType' then
      validateType(type.type)
    elseif type.kind == 'namedType' then
      local schemaType = context.schema:getType(type.name.value)
      if not schemaType then
        error('Variable specifies unknown type "' .. tostring(type.name.value) .. '"')
      elseif schemaType.__type ~= 'Scalar' and schemaType.__type ~= 'Enum' and schemaType.__type ~= 'InputObject' then
        error('Variable types must be scalars, enums, or input objects, got "' .. schemaType.__type .. '"')
      end
    end
  end

  if node.variableDefinitions then
    for _, definition in ipairs(node.variableDefinitions) do
      validateType(definition.type)
    end
  end
end

function rules.variableDefaultValuesHaveCorrectType(node, context)
  if node.variableDefinitions then
    for _, definition in ipairs(node.variableDefinitions) do
      if definition.type.kind == 'nonNullType' and definition.defaultValue then
        error('Non-null variables can not have default values')
      elseif definition.defaultValue then
        local variableType = query_util.typeFromAST(definition.type, context.schema)
        util.coerceValue(definition.defaultValue, variableType)
      end
    end
  end
end

function rules.variablesAreUsed(node, context)
  if node.variableDefinitions then
    for _, definition in ipairs(node.variableDefinitions) do
      local variableName = definition.variable.name.value
      if not context.variableReferences[variableName] then
        error('Unused variable "' .. variableName .. '"')
      end
    end
  end
end

function rules.variablesAreDefined(node, context)
  if context.variableReferences then
    local variableMap = {}
    for _, definition in ipairs(node.variableDefinitions or {}) do
      variableMap[definition.variable.name.value] = true
    end

    for variable in pairs(context.variableReferences) do
      if not variableMap[variable] then
        error('Unknown variable "' .. variable .. '"')
      end
    end
  end
end

-- {{{ variableUsageAllowed

local function collectArguments(referencedNode, context, seen, arguments)
  if referencedNode.kind == 'selectionSet' then
    for _, selection in ipairs(referencedNode.selections) do
      if not seen[selection] then
        seen[selection] = true
        collectArguments(selection, context, seen, arguments)
      end
    end
  elseif referencedNode.kind == 'field' and referencedNode.arguments then
    local fieldName = referencedNode.name.value
    arguments[fieldName] = arguments[fieldName] or {}
    for _, argument in ipairs(referencedNode.arguments) do
      table.insert(arguments[fieldName], argument)
    end
  elseif referencedNode.kind == 'inlineFragment' then
    return collectArguments(referencedNode.selectionSet, context, seen,
      arguments)
  elseif referencedNode.kind == 'fragmentSpread' then
    local fragment = context.fragmentMap[referencedNode.name.value]
    return fragment and collectArguments(fragment.selectionSet, context, seen,
      arguments)
  end
end

-- http://facebook.github.io/graphql/June2018/#AreTypesCompatible()
local function isTypeSubTypeOf(subType, superType, context)
  if subType == superType then return true end

  if superType.__type == 'NonNull' then
    if subType.__type == 'NonNull' then
      return isTypeSubTypeOf(subType.ofType, superType.ofType, context)
    end

    return false
  elseif subType.__type == 'NonNull' then
    return isTypeSubTypeOf(subType.ofType, superType, context)
  end

  if superType.__type == 'List' then
    if subType.__type == 'List' then
      return isTypeSubTypeOf(subType.ofType, superType.ofType, context)
    end

    return false
  elseif subType.__type == 'List' then
    return false
  end

  return false
end

local function isVariableTypesValid(argument, argumentType, context,
    variableMap)
  if argument.value.kind == 'variable' then
    -- found a variable, check types compatibility
    local variableName = argument.value.name.value
    local variableDefinition = variableMap[variableName]

    if variableDefinition == nil then
      -- The same error as in rules.variablesAreDefined().
      error('Unknown variable "' .. variableName .. '"')
    end

    local hasDefault = variableDefinition.defaultValue ~= nil

    local variableType = query_util.typeFromAST(variableDefinition.type,
      context.schema)

    if hasDefault and variableType.__type ~= 'NonNull' then
      variableType = types.nonNull(variableType)
    end

    if not isTypeSubTypeOf(variableType, argumentType, context) then
      return false, ('Variable "%s" type mismatch: the variable type "%s" ' ..
        'is not compatible with the argument type "%s"'):format(variableName,
        util.getTypeName(variableType), util.getTypeName(argumentType))
    end
  elseif argument.value.kind == 'list' then
    -- find variables deeper
    local parentType = argumentType
    if parentType.__type == 'NonNull' then
      parentType = parentType.ofType
    end
    local childType = parentType.ofType

    for _, child in ipairs(argument.value.values) do
      local ok, err = isVariableTypesValid({value = child}, childType, context,
              variableMap)
      if not ok then return false, err end
    end
  elseif argument.value.kind == 'inputObject' then
    -- find variables deeper
    for _, child in ipairs(argument.value.values) do
      local isInputObject = argumentType.__type == 'InputObject'

      if isInputObject then
        local childArgumentType = argumentType.fields[child.name].kind
        local ok, err = isVariableTypesValid(child, childArgumentType, context,
          variableMap)
        if not ok then return false, err end
      end
    end
  end
  return true
end

function rules.variableUsageAllowed(node, context)
  if not context.currentOperation then return end

  local variableMap = {}
  local variableDefinitions = context.currentOperation.variableDefinitions
  for _, definition in ipairs(variableDefinitions or {}) do
    variableMap[definition.variable.name.value] = definition
  end

  local arguments

  if node.kind == 'field' then
    arguments = { [node.name.value] = node.arguments }
  elseif node.kind == 'fragmentSpread' then
    local seen = {}
    local fragment = context.fragmentMap[node.name.value]
    if fragment then
      arguments = {}
      collectArguments(fragment.selectionSet, context, seen, arguments)
    end
  end

  if not arguments then return end

  for field in pairs(arguments) do
    local parentField = getParentField(context, field)
    for i = 1, #arguments[field] do
      local argument = arguments[field][i]
      local argumentType = parentField.arguments[argument.name.value]
      local ok, err = isVariableTypesValid(argument, argumentType, context,
        variableMap)
      if not ok then
        error(err)
      end
    end
  end
end

-- }}}

return rules
