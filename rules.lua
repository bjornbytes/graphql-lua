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
    for _, argument in pairs(node.arguments) do
      local name = argument.name.value
      if not context.currentField.arguments[name] then
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

  -- FIXME
  local function canMerge(fieldA, fieldB)
    return fieldA.__type == fieldB.__type and fieldA.name == fieldB.name
  end

  local function validateSelection(key, kind)
    if selectionMap[key] and not canMerge(selectionMap[key], kind) then
      error('Type mismatch')
    end

    selectionMap[key] = kind
  end

  -- Recursively make sure that there are no ambiguous selections with the same name.
  local function validateSelectionSet(selectionSet)
    for _, selection in ipairs(selectionSet.selections) do
      if selection.kind == 'field' then
        local selectionKey = selection.alias and selection.alias.name.value or selection.name.value
        local currentType = context.objects[#context.objects].fields[selection.name.value].kind
        validateSelection(selectionKey, currentType)
      elseif selection.kind == 'inlineFragment' then
        validateSelectionSet(selection.selectionSet)
      elseif selection.kind == 'fragmentSpread' then
        validateSelectionSet(selection.selectionSet)
      end
    end
  end

  validateSelectionSet(node)
end

return rules
