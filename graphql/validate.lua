local path = (...):gsub('%.[^%.]+$', '')
local rules = require(path .. '.rules')
local util = require(path .. '.util')
local introspection = require(path .. '.introspection')
local schema = require(path .. '.schema')

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
      table.insert(context.objects, context.schema[node.operation])
      context.currentOperation = node
      context.variableReferences = {}
    end,

    exit = function(node, context)
      table.remove(context.objects)
      context.currentOperation = nil
      context.variableReferences = nil
    end,

    children = function(node)
      return { node.selectionSet }
    end,

    rules = {
      rules.uniqueOperationNames,
      rules.loneAnonymousOperation,
      rules.directivesAreDefined,
      rules.variablesHaveCorrectType,
      rules.variableDefaultValuesHaveCorrectType,
      exit = {
        rules.variablesAreUsed,
        rules.variablesAreDefined
      }
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
      local name = node.name.value

      if introspection.fieldMap[name] then
        table.insert(context.objects, introspection.fieldMap[name].kind)
      else
        local parentField = getParentField(context, name, 0)
        -- false is a special value indicating that the field was not present in the type definition.
        table.insert(context.objects, parentField and parentField.kind or false)
      end
    end,

    exit = function(node, context)
      table.remove(context.objects)
    end,

    children = function(node)
      local children = {}

      if node.arguments then
        for i = 1, #node.arguments do
          table.insert(children, node.arguments[i])
        end
      end

      if node.directives then
        for i = 1, #node.directives do
          table.insert(children, node.directives[i])
        end
      end

      if node.selectionSet then
        table.insert(children, node.selectionSet)
      end

      return children
    end,

    rules = {
      rules.fieldsDefinedOnType,
      rules.argumentsDefinedOnType,
      rules.scalarFieldsAreLeaves,
      rules.compositeFieldsAreNotLeaves,
      rules.uniqueArgumentNames,
      rules.argumentsOfCorrectType,
      rules.requiredArgumentsPresent,
      rules.directivesAreDefined,
      rules.variableUsageAllowed
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

    rules = {
      rules.fragmentHasValidType,
      rules.fragmentSpreadIsPossible,
      rules.directivesAreDefined
    }
  },

  fragmentSpread = {
    enter = function(node, context)
      context.usedFragments[node.name.value] = true

      local fragment = context.fragmentMap[node.name.value]

      if not fragment then return end

      local fragmentType = context.schema:getType(fragment.typeCondition.name.value) or false

      table.insert(context.objects, fragmentType)

      if context.currentOperation then
        local seen = {}
        local function collectTransitiveVariables(referencedNode)
          if not referencedNode then return end

          if referencedNode.kind == 'selectionSet' then
            for _, selection in ipairs(referencedNode.selections) do
              if not seen[selection] then
                seen[selection] = true
                collectTransitiveVariables(selection)
              end
            end
          elseif referencedNode.kind == 'field' then
            if referencedNode.arguments then
              for _, argument in ipairs(referencedNode.arguments) do
                collectTransitiveVariables(argument)
              end
            end

            if referencedNode.selectionSet then
              collectTransitiveVariables(referencedNode.selectionSet)
            end
          elseif referencedNode.kind == 'argument' then
            return collectTransitiveVariables(referencedNode.value)
          elseif referencedNode.kind == 'listType' or referencedNode.kind == 'nonNullType' then
            return collectTransitiveVariables(referencedNode.type)
          elseif referencedNode.kind == 'variable' then
            context.variableReferences[referencedNode.name.value] = true
          elseif referencedNode.kind == 'inlineFragment' then
            return collectTransitiveVariables(referencedNode.selectionSet)
          elseif referencedNode.kind == 'fragmentSpread' then
            local fragment = context.fragmentMap[referencedNode.name.value]
            context.usedFragments[referencedNode.name.value] = true
            return fragment and collectTransitiveVariables(fragment.selectionSet)
          end
        end

        collectTransitiveVariables(fragment.selectionSet)
      end
    end,

    exit = function(node, context)
      table.remove(context.objects)
    end,

    rules = {
      rules.fragmentSpreadTargetDefined,
      rules.fragmentSpreadIsPossible,
      rules.directivesAreDefined,
      rules.variableUsageAllowed
    }
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
      local children = {}

      for _, selection in ipairs(node.selectionSet) do
        table.insert(children, selection)
      end

      return children
    end,

    rules = {
      rules.fragmentHasValidType,
      rules.fragmentDefinitionHasNoCycles,
      rules.directivesAreDefined
    }
  },

  argument = {
    enter = function(node, context)
      if context.currentOperation then
        local value = node.value
        while value.kind == 'listType' or value.kind == 'nonNullType' do
          value = value.type
        end

        if value.kind == 'variable' then
          context.variableReferences[value.name.value] = true
        end
      end
    end,

    rules = { rules.uniqueInputObjectFields }
  },

  directive = {
    children = function(node, context)
      return node.arguments
    end
  }
}

return function(schema, tree)
  local context = {
    schema = schema,
    fragmentMap = {},
    operationNames = {},
    hasAnonymousOperation = false,
    usedFragments = {},
    objects = {},
    currentOperation = nil,
    variableReferences = nil
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
