local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')
local schema = require(path .. '.schema')
local introspection = require(path .. '.introspection')

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
  if context.objects[#context.objects].__type == 'Scalar' and node.selectionSet then
    error('Scalar values cannot have subselections')
  end
end

function rules.compositeFieldsAreNotLeaves(node, context)
  local _type = context.objects[#context.objects].__type
  local isCompositeType = _type == 'Object' or _type == 'Interface' or _type == 'Union'

  if isCompositeType and not node.selectionSet then
    error('Composite types must have subselections')
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
        local parentType = selection.typeCondition and context.schema:getType(selection.typeCondition.name.value) or parentType
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

function rules.uniqueArgumentNames(node, context)
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

function rules.uniqueFragmentNames(node, context)
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
    return fragmentTypes[kind]
  end)

  if not valid then
    error('Fragment type condition is not possible for given type')
  end
end

function rules.uniqueInputObjectFields(node, context)
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

  validateValue(node.value)
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
        util.coerceValue(definition.defaultValue, context.schema:getType(definition.type.name.value))
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

function rules.variableUsageAllowed(node, context)
  if context.currentOperation then
    local variableMap = {}
    for _, definition in ipairs(context.currentOperation.variableDefinitions or {}) do
      variableMap[definition.variable.name.value] = definition
    end

    local arguments

    if node.kind == 'field' then
      arguments = { [node.name.value] = node.arguments }
    elseif node.kind == 'fragmentSpread' then
      local seen = {}
      local function collectArguments(referencedNode)
        if referencedNode.kind == 'selectionSet' then
          for _, selection in ipairs(referencedNode.selections) do
            if not seen[selection] then
              seen[selection] = true
              collectArguments(selection)
            end
          end
        elseif referencedNode.kind == 'field' and referencedNode.arguments then
          local fieldName = referencedNode.name.value
          arguments[fieldName] = arguments[fieldName] or {}
          for _, argument in ipairs(referencedNode.arguments) do
            table.insert(arguments[fieldName], argument)
          end
        elseif referencedNode.kind == 'inlineFragment' then
          return collectArguments(referencedNode.selectionSet)
        elseif referencedNode.kind == 'fragmentSpread' then
          local fragment = context.fragmentMap[referencedNode.name.value]
          return fragment and collectArguments(fragment.selectionSet)
        end
      end

      local fragment = context.fragmentMap[node.name.value]
      if fragment then
        arguments = {}
        collectArguments(fragment.selectionSet)
      end
    end

    if not arguments then return end

    for field in pairs(arguments) do
      local parentField = getParentField(context, field)
      for i = 1, #arguments[field] do
        local argument = arguments[field][i]
        if argument.value.kind == 'variable' then
          local argumentType = parentField.arguments[argument.name.value]

          local variableName = argument.value.name.value
          local variableDefinition = variableMap[variableName]
          local hasDefault = variableDefinition.defaultValue ~= nil

          local function typeFromAST(variable)
            local innerType
            if variable.kind == 'listType' then
              innerType = typeFromAST(variable.type)
              return innerType and types.list(innerType)
            elseif variable.kind == 'nonNullType' then
              innerType = typeFromAST(variable.type)
              return innerType and types.nonNull(innerType)
            else
              assert(variable.kind == 'namedType', 'Variable must be a named type')
              return context.schema:getType(variable.name.value)
            end
          end

          local variableType = typeFromAST(variableDefinition.type)

          if hasDefault and variableType.__type ~= 'NonNull' then
            variableType = types.nonNull(variableType)
          end

          local function isTypeSubTypeOf(subType, superType)
            if subType == superType then return true end

            if superType.__type == 'NonNull' then
              if subType.__type == 'NonNull' then
                return isTypeSubTypeOf(subType.ofType, superType.ofType)
              end

              return false
            elseif subType.__type == 'NonNull' then
              return isTypeSubTypeOf(subType.ofType, superType)
            end

            if superType.__type == 'List' then
              if subType.__type == 'List' then
                return isTypeSubTypeOf(subType.ofType, superType.ofType)
              end

              return false
            elseif subType.__type == 'List' then
              return false
            end

            if subType.__type ~= 'Object' then return false end

            if superType.__type == 'Interface' then
              local implementors = context.schema:getImplementors(superType.name)
              return implementors and implementors[context.schema:getType(subType.name)]
            elseif superType.__type == 'Union' then
              local types = superType.types
              for i = 1, #types do
                if types[i] == subType then
                  return true
                end
              end

              return false
            end

            return false
          end

          if not isTypeSubTypeOf(variableType, argumentType) then
            error('Variable type mismatch')
          end
        end
      end
    end
  end
end

return rules
