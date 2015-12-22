local function getArgumentValue(value, context)
  return nil -- TODO
end

local function getFieldEntryKey(selection)
  return selection.alias and selection.alias.name.value or selection.name.value
end

local function shouldIncludeNode(selection, context)
  if selection.directives then
    for _, directive in ipairs(selection.directives) do
      if directive.name.value == 'skip' then
        for _, argument in ipairs(directive.arguments) do
          if argument.name == 'if' and getArgumentValue(argument.value, context) then
            return false
          end
        end
      elseif directive.name.value == 'include' then
        for _, argument in ipairs(directive.arguments) do
          if argument.name == 'if' and not getArgumentValue(argument.value, context) then
            return false
          end
        end
      end
    end
  end

  return true
end

local function collectFields(selectionSet, type, fields, visitedFragments, context)
  for _, selection in ipairs(selectionSet.selections) do
    if selection.kind == 'field' then
      if shouldIncludeNode(selection) then
        local name = getFieldEntryKey(selection)
        fields[name] = fields[name] or {}
        table.insert(fields[name], selection)
      end
    elseif selection.kind == 'inlineFragment' then
      if shouldIncludeNode(selection) and doesFragmentApply(selection, type) then
        collectFields(selection.selectionSet, type, fields, visitedFragments, context)
      end
    elseif selection.kind == 'fragmentSpread' then
      local fragmentName = selection.name.value
      if shouldIncludeNode(selection) and not visitedFragments[fragmentName] then
        visitedFragments[fragmentName] = true
        local fragment = context.fragmentMap[fragmentName]
        if fragment and shouldIncludeNode(fragment) and doesFragmentApply(fragment, type) then
          collectFields(fragment.selectionSet, type, fields, visitedFragments, context)
        end
      end
    end
  end

  return fields
end

local function buildContext(schema, tree, variables, operationName)
  local context = {
    schema = schema,
    operation = nil,
    fragmentMap = {}
  }

  for _, definition in ipairs(tree.definitions) do
    if definition.kind == 'operation' then
      if not operationName and context.operation then
        error('Operation name must be specified if more than one operation exists.')
      end

      if not operationName or definition.name.value == operationName then
        context.operation = definition
      end
    elseif definition.kind == 'fragmentDefinition' then
      context.fragmentMap[definition.name.value] = definition
    end
  end

  if not context.operation then
    if operationName then
      error('Unknown operation "' .. operationName .. '"')
    else
      error('Must provide an operation')
    end
  end

  return context
end

return function(schema, tree, variables, operationName)
  local context = buildContext(schema, tree, variables, operationName)
  local rootType = schema[context.operation.operation]

  if not rootType then
    error('Unsupported operation "' .. context.operation.operation .. '"')
  end

  local fields = collectFields(context.operation.selectionSet, rootType, {}, {}, context)
end
