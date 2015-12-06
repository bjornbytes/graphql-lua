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
      if context.typeStack[#context.typeStack].__type == 'Scalar' and node.selectionSet then
        error('Scalar values cannot have selections')
      end

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
        table.insert(context.typeStack, parent.fields[node.name.value].kind)
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
