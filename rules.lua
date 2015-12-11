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
  if context.currentField == false then
    local parent = context.objects[#context.objects - 1]
    error('Field "' .. node.name.value .. '" is not defined on type "' .. parent.name .. '"')
  end
end

function rules.argumentsDefinedOnType(node, context)
  if node.arguments then
    local parentField = context.objects[#context.objects - 1].fields[node.name.value]
    for _, argument in pairs(node.arguments) do
      local name = argument.name.value
      if not parentField.arguments[name] then
        error('Non-existent argument "' .. name .. '"')
      end
    end
  end
end

function rules.scalarFieldsAreLeaves(node, context)
  if context.currentField.__type == 'Scalar' and node.selectionSet then
    error('Scalar values cannot have subselections')
  end
end

function rules.compositeFieldsAreNotLeaves(node, context)
  local _type = context.currentField.__type
  local isCompositeType = _type == 'Object' or _type == 'Interface' or _type == 'Union'

  if isCompositeType and not node.selectionSet then
    error('Composite types must have subselections')
  end
end

function rules.inlineFragmentValidTypeCondition(node, context)
  if not node.typeCondition then return end

  local kind = context.objects[#context.objects]

  if kind == false then
    error('Inline fragment type condition refers to non-existent type')
  end

  if kind.__type ~= 'Object' and kind.__type ~= 'Interface' and kind.__type ~= 'Union' then
    error('Inline fragment type condition was not an Object, Interface, or Union')
  end
end

function rules.unambiguousSelections(node, context)
  local selectionMap = {}

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
        local key = selection.alias and selection.alias.name.value or selection.name.value
        local definition = parentType.fields[selection.name.value].kind
        local fieldEntry = {
          parent = parentType,
          field = selection,
          definition = definition
        }

        validateField(key, fieldEntry)
      elseif selection.kind == 'inlineFragment' then
        local parentType = parentType

        if selection.typeCondition then
          parentType = context.schema:getType(selection.typeCondition.name.value) or parentType
        end

        validateSelectionSet(selection.selectionSet, parentType)
      elseif selection.kind == 'fragmentSpread' then
        -- FIXME find fragment by name, get type condition to compute parentType
        validateSelectionSet(selection.selectionSet, parentType)
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
  local function validateType(argumentType, valueNode)
    if argumentType.__type == 'NonNull' then
      return validateType(argumentType.ofType, valueNode)
    end

    if argumentType.__type == 'List' then
      if valueNode.kind ~= 'list' then
        error('Expected a list')
      end

      for i = 1, #valueNode.values do
        validateType(argumentType.ofType, valueNode.values[i])
      end
    end

    if argumentType.__type == 'InputObject' then
      if valueNode.kind ~= 'object' then
        error('Expected an object')
      end

      for _, field in ipairs(valueNode.values) do
        if not argumentType.fields[field.name] then
          error('Unknown input object field "' .. field.name .. '"')
        end

        validateType(argumentType.fields[field.name].kind, field.value)
      end
    end

    if argumentType.__type == 'Enum' then
      if valueNode.kind ~= 'enum' then
        error('Expected enum value, got ' .. valueNode.kind)
      end

      if not argumentType.values[valueNode.value] then
        error('Invalid enum value "' .. valueNode.value .. '"')
      end
    end

    if argumentType.__type == 'Scalar' then
      if argumentType.parseLiteral(valueNode) == nil then
        error('Could not coerce "' .. valueNode.value .. '" to "' .. argumentType.name .. '"')
      end
    end
  end

  if node.arguments then
    local parentField = context.objects[#context.objects - 1].fields[node.name.value]
    for _, argument in pairs(node.arguments) do
      local name = argument.name.value
      local argumentType = parentField.arguments[name]
      validateType(argumentType, argument.value)
    end
  end
end

return rules
