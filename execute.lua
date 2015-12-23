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

local function defaultResolver(source, arguments, info)
  local property = source[info.fieldName]
  return type(property) == 'function' and property(source) or property
end

local function getFieldEntryKey(selection)
  return selection.alias and selection.alias.name.value or selection.name.value
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

local function collectFields(selectionSet, type, fields, visitedFragments, context)
  for _, selection in ipairs(selectionSet.selections) do
    if selection.kind == 'field' then
      if shouldIncludeNode(selection) then
        local name = getFieldEntryKey(selection)
        fields[name] = fields[name] or {}
        table.insert(fields[name], selection)
      end
    elseif selection.kind == 'inlineFragment' then
      if shouldIncludeNode(selection) and doesFragmentApply(selection, type, context) then
        collectFields(selection.selectionSet, type, fields, visitedFragments, context)
      end
    elseif selection.kind == 'fragmentSpread' then
      local fragmentName = selection.name.value
      if shouldIncludeNode(selection) and not visitedFragments[fragmentName] then
        visitedFragments[fragmentName] = true
        local fragment = context.fragmentMap[fragmentName]
        if fragment and shouldIncludeNode(fragment) and doesFragmentApply(fragment, type, context) then
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

local function executeFields(parentType, rootValue, fieldGroups, context)
  local result = {}

  for name, fieldGroup in pairs(fieldGroups) do
    result[name] = resolveField(parentType, rootValue, fieldGroup, context)
  end

  return result
end

local function resolveField(parentType, rootValue, fields, context)
  local field = fields[1]
  local fieldName = field.name.value

  local fieldType = parentType.fields[fieldName]
  local returnType = fieldType.kind

  local info = {
    fieldName = fieldName,
    fields = fields,
    returnType = returnType,
    parentType = parentType,
    schema = context.schema,
    fragments = context.fragmentMap,
    rootValue = rootValue,
    operation = context.operation,
    variables = context.variables
  }

  local resolve = fieldType.resolve or defaultResolver

  local result = resolve(source, {}, info)
end

return function(schema, tree, rootValue, variables, operationName)
  local context = buildContext(schema, tree, variables, operationName)
  local rootType = schema[context.operation.operation]

  if not rootType then
    error('Unsupported operation "' .. context.operation.operation .. '"')
  end

  local fieldGroups = collectFields(context.operation.selectionSet, rootType, {}, {}, context)
  return executeFields(rootType, rootValue, fieldGroups, context)
end
