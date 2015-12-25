local types = require 'types'
local util = require 'util'

local function typeFromAST(node, schema)
  local innerType
  if node.kind == 'listType' then
    innerType = typeFromAST(node.type)
    return innerType and types.list(innerType)
  elseif node.kind == 'nonNullType' then
    innerType = typeFromAST(node.type)
    return innerType and types.nonNull(innerType)
  else
    assert(node.kind == 'namedType', 'Variable must be a named type')
    return schema:getType(node.name.value)
  end
end

local function getFieldResponseKey(field)
  return field.alias and field.alias.name.value or field.name.value
end

local function shouldIncludeNode(selection, context)
  if selection.directives then
    local function isDirectiveActive(key, _type)
      local directive = util.find(selection.directives, function(directive)
        return directive.name.value == key
      end)

      if not directive then return end

      local ifArgument = util.find(directive.arguments, function(argument)
        return argument.name.value == 'if'
      end)

      if not ifArgument then return end

      return util.coerceValue(ifArgument.value, _type.arguments['if'])
    end

    if isDirectiveActive('skip', types.skip) then return false end
    if isDirectiveActive('include', types.include) == false then return false end
  end

  return true
end

local function doesFragmentApply(fragment, type, context)
  if not fragment.typeCondition then return true end

  local innerType = typeFromAST(fragment.typeCondition, context.schema)

  if innerType == type then
    return true
  elseif innerType.__type == 'Interface' then
    return schema:getImplementors(type)[innerType]
  elseif innerType.__type == 'Union' then
    return util.find(type.types, function(member)
      return member == innerType
    end)
  end
end

local function mergeSelectionSets(fields)
  local selectionSet = {}

  for i = 1, #fields do
    local selectionSet = fields[i].selectionSet
    if selectionSet then
      for j = 1, #selectionSet.selections do
        table.insert(selectionSet, selectionSet.selections[j])
      end
    end
  end

  return selectionSet
end

local function defaultResolver(object, fields, info)
  return object[fields[1].name.value]
end

local function buildContext(schema, tree, variables, operationName)
  local context = {
    schema = schema,
    variables = variables,
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

local function collectFields(objectType, selectionSet, visitedFragments, result, context)
  for _, selection in ipairs(selectionSet.selections) do
    if selection.kind == 'field' then
      if shouldIncludeNode(selection) then
        local name = getFieldResponseKey(selection)
        result[name] = result[name] or {}
        table.insert(result[name], selection)
      end
    elseif selection.kind == 'inlineFragment' then
      if shouldIncludeNode(selection) and doesFragmentApply(selection, objectType, context) then
        collectFields(objectType, selection.selectionSet, visitedFragments, result, context)
      end
    elseif selection.kind == 'fragmentSpread' then
      local fragmentName = selection.name.value
      if shouldIncludeNode(selection) and not visitedFragments[fragmentName] then
        visitedFragments[fragmentName] = true
        local fragment = context.fragmentMap[fragmentName]
        if fragment and shouldIncludeNode(fragment) and doesFragmentApply(fragment, objectType, context) then
          collectFields(objectType, fragment.selectionSet, visitedFragments, result, context)
        end
      end
    end
  end

  return result
end

local function completeValue(fieldType, result, subSelectionSet)
  return result -- TODO
end

local function getFieldEntry(objectType, object, fields)
  local firstField = fields[1]
  local responseKey = getFieldResponseKey(firstField)
  local fieldType = objectType.fields[firstField.name.value]

  if fieldType == nil then
    return nil
  end

  -- TODO correct arguments to resolve
  local resolvedObject = (fieldType.resolve or defaultResolver)(object, fields, {})

  if not resolvedObject then
    return nil -- TODO null
  end

  local subSelectionSet = mergeSelectionSets(fields)
  local responseValue = completeValue(fieldType, resolvedObject, subSelectionSet)
  return responseValue
end

local function evaluateSelectionSet(objectType, object, selectionSet, context)
  local groupedFieldSet = collectFields(objectType, selectionSet, {}, {}, context)

  return util.map(groupedFieldSet, function(fields)
    return getFieldEntry(objectType, object, fields)
  end)
end

return function(schema, tree, variables, operationName, rootValue)
  local context = buildContext(schema, tree, variables, operationName)
  local rootType = schema[context.operation.operation]

  if not rootType then
    error('Unsupported operation "' .. context.operation.operation .. '"')
  end

  return evaluateSelectionSet(rootType, rootValue, context.operation.selectionSet, context)
end
