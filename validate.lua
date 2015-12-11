local rules = require 'rules'

local visitors = {
  document = {
    enter = function(node, context)
      for _, definition in ipairs(node.definitions) do
        if definition.kind == 'fragmentDefinition' then
          context.fragmentMap[definition.name.value] = definition
        end
      end
    end,

    children = function(node, context)
      return node.definitions
    end,

    rules = { rules.uniqueFragmentNames, exit = { rules.noUnusedFragments } }
  },

  operation = {
    enter = function(node, context)
      table.insert(context.objects, context.schema.query)
    end,

    exit = function(node, context)
      table.remove(context.objects)
    end,

    children = function(node)
      return { node.selectionSet }
    end,

    rules = {
      rules.uniqueOperationNames,
      rules.loneAnonymousOperation
    }
  },

  selectionSet = {
    children = function(node)
      return node.selections
    end,

    rules = { rules.unambiguousSelections }
  },

  field = {
    enter = function(node, context)
      local parentField = context.objects[#context.objects].fields[node.name.value]

      -- false is a special value indicating that the field was not present in the type definition.
      context.currentField = parentField and parentField.kind or false

      table.insert(context.objects, context.currentField)
    end,

    exit = function(node, context)
      table.remove(context.objects)
      context.currentField = nil
    end,

    children = function(node)
      if node.selectionSet then
        return {node.selectionSet}
      end
    end,

    rules = {
      rules.fieldsDefinedOnType,
      rules.argumentsDefinedOnType,
      rules.scalarFieldsAreLeaves,
      rules.compositeFieldsAreNotLeaves,
      rules.uniqueArgumentNames,
      rules.argumentsOfCorrectType,
      rules.requiredArgumentsPresent
    }
  },

  inlineFragment = {
    enter = function(node, context)
      local kind = false

      if node.typeCondition then
        kind = context.schema:getType(node.typeCondition.name.value) or false
      end

      table.insert(context.objects, kind)
    end,

    exit = function(node, context)
      table.remove(context.objects)
    end,

    children = function(node, context)
      if node.selectionSet then
        return {node.selectionSet}
      end
    end,

    rules = { rules.fragmentHasValidType }
  },

  fragmentSpread = {
    enter = function(node, context)
      context.usedFragments[node.name.value] = true
    end,

    rules = { rules.fragmentSpreadTargetDefined }
  },

  fragmentDefinition = {
    enter = function(node, context)
      kind = context.schema:getType(node.typeCondition.name.value) or false
      table.insert(context.objects, kind)
    end,

    exit = function(node, context)
      table.remove(context.objects)
    end,

    children = function(node)
      return { node.selectionSet }
    end,

    rules = { rules.fragmentHasValidType, rules.fragmentDefinitionHasNoCycles }
  }
}

return function(schema, tree)
  local context = {
    schema = schema,
    fragmentMap = {},
    operationNames = {},
    hasAnonymousOperation = false,
    usedFragments = {},
    objects = {}
  }

  local function visit(node)
    local visitor = node.kind and visitors[node.kind]

    if not visitor then return end

    if visitor.enter then
      visitor.enter(node, context)
    end

    if visitor.rules then
      for i = 1, #visitor.rules do
        visitor.rules[i](node, context)
      end
    end

    if visitor.children then
      local children = visitor.children(node)
      if children then
        for _, child in ipairs(children) do
          visit(child)
        end
      end
    end

    if visitor.rules and visitor.rules.exit then
      for i = 1, #visitor.rules.exit do
        visitor.rules.exit[i](node, context)
      end
    end

    if visitor.exit then
      visitor.exit(node, context)
    end
  end

  return visit(tree)
end
