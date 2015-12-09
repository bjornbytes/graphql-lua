return function(schema, tree)

  local context = {
    operationNames = {},
    hasAnonymousOperation = false,
    typeStack = {}
  }

  local visitors = {
    document = function(node)
      return node.definitions
    end,

    operation = function(node)
      local name = node.name and node.name.value

      if name then
        if context.operationNames[name] then
          error('Multiple operations exist named "' .. name .. '"')
        else
          context.operationNames[name] = true
        end
      else
        if context.hasAnonymousOperation or next(context.operationNames) then
          error('Cannot have more than one operation when using anonymous operations')
        end

        context.hasAnonymousOperation = true
      end

      return {node.selectionSet}
    end,

    selectionSet = function(node)
      return node.selections
    end,

    field = function(node)
      local currentType = context.typeStack[#context.typeStack].__type
      if currentType == 'Scalar' and node.selectionSet then
        error('Scalar values cannot have subselections')
      end

      local isCompositeType = currentType == 'Object' or currentType == 'Interface' or currentType == 'Union'
      if isCompositeType and not node.selectionSet then
        error('Composite types must have subselections')
      end

      if node.selectionSet then
        return {node.selectionSet}
      end
    end,

    inlineFragment = function(node)
      if node.selectionSet then
        return {node.selectionSet}
      end
    end
  }

  local root = schema.query
  local function visit(node)
    if node.kind and visitors[node.kind] then
      if node.kind == 'operation' then
        table.insert(context.typeStack, schema.query)
      elseif node.kind == 'field' then
        local parent = context.typeStack[#context.typeStack]
        if parent.fields[node.name.value] then
          table.insert(context.typeStack, parent.fields[node.name.value].kind)
        else
          error('Field "' .. node.name.value .. '" is not defined on type "' .. parent.name .. '"')
        end
      elseif node.kind == 'inlineFragment' then
        if node.typeCondition then
          local kind = schema:getType(node.typeCondition.name.value)

          if not kind then
            error('Inline fragment type condition refers to non-existent type')
          end

          if kind and kind.__type ~= 'Object' and kind.__type ~= 'Interface' and kind.__type ~= 'Union' then
            error('Inline fragment type condition was not an Object, Interface, or Union')
          end

          table.insert(context.typeStack, kind)
        end
      end

      local targets = visitors[node.kind](node)
      if targets then
        for _, target in ipairs(targets) do
          visit(target)
        end
      end
    end
  end

  visit(tree)
end
