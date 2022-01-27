local introspection = require('graphql.introspection')
local types = require('graphql.types')

local function error(...)
  return _G.error(..., 0)
end

local schema = {}
schema.__index = schema

function schema.create(config, name, opts)
  assert(type(config.query) == 'table', 'must provide query object')
  assert(not config.mutation or type(config.mutation) == 'table', 'mutation must be a table if provided')

  opts = opts or {}
  local self = setmetatable({}, schema)

  for k, v in pairs(config) do
    self[k] = v
  end

  self.directives = self.directives or {
    types.include,
    types.skip,
    types.specifiedBy,
  }

  self.typeMap = {}
  self.interfaceMap = {}
  self.directiveMap = {}
  self.name = name

  self:generateTypeMap(self.query)
  self:generateTypeMap(self.mutation)
  self:generateTypeMap(introspection.__Schema)
  self:generateDirectiveMap()

  if opts.defaultValues == true then
    self.defaultValues = {}
    self.defaultValues.mutation = self:extractDefaults(self.mutation)
    self.defaultValues.query = self:extractDefaults(self.query)
  end

  if opts.directivesDefaultValues == true then
    self.directivesDefaultValues = {}

    for directiveName, directive in pairs(self.directiveMap or {}) do
      self.directivesDefaultValues[directiveName] = self:extractDefaults(directive)
    end
  end

  return self
end

function schema:extractDefaults(node)
  if not node then return end

  local defaultValues
  local nodeType = node.__type ~= nil and node or node.kind

  if nodeType.__type == 'NonNull' then
    return self:extractDefaults(nodeType.ofType)
  end

  if nodeType.__type == 'Enum' then
    return node.defaultValue
  end

  if nodeType.__type == 'Scalar' then
    return node.defaultValue
  end

  node.fields = type(node.fields) == 'function' and node.fields() or node.fields

  if nodeType.__type == 'Object' or nodeType.__type == 'InputObject' then
    for fieldName, field in pairs(nodeType.fields or {}) do
      local fieldDefaultValue = self:extractDefaults(field)
      if fieldDefaultValue ~= nil then
        defaultValues = defaultValues or {}
        defaultValues[fieldName] = fieldDefaultValue
      end

      for argumentName, argument in pairs(field.arguments or {}) do
        -- BEGIN_HACK: resolve type names to real types
        if type(argument) == 'string' then
          argument = types.resolve(argument, self.name)
          field.arguments[argumentName] = argument
        end

        if type(argument.kind) == 'string' then
          argument.kind = types.resolve(argument.kind, self.name)
        end
        -- END_HACK: resolve type names to real types

        local argumentDefaultValue = self:extractDefaults(argument)
        if argumentDefaultValue ~= nil then
          defaultValues = defaultValues or {}
          defaultValues[fieldName] = defaultValues[fieldName] or {}
          defaultValues[fieldName][argumentName] = argumentDefaultValue
        end
      end
    end
    return defaultValues
  end

  if nodeType.__type =='Directive' then
      for argumentName, argument in pairs(nodeType.arguments or {}) do
        -- BEGIN_HACK: resolve type names to real types
        if type(argument) == 'string' then
          argument = types.resolve(argument, self.name)
          nodeType.arguments[argumentName] = argument
        end

        if type(argument.kind) == 'string' then
          argument.kind = types.resolve(argument.kind, self.name)
        end
        -- END_HACK: resolve type names to real types

        local argumentDefaultValue = self:extractDefaults(argument)
        if argumentDefaultValue ~= nil then
          defaultValues = defaultValues or {}
          defaultValues[argumentName] = argumentDefaultValue
        end
      end
    return defaultValues
  end

  if nodeType.__type == 'List' then
    return self:extractDefaults(nodeType.ofType)
  end
end

function schema:generateTypeMap(node)
  if not node or (self.typeMap[node.name] and self.typeMap[node.name] == node) then return end

  if node.__type == 'NonNull' or node.__type == 'List' then
    -- HACK: resolve type names to real types
    node.ofType = types.resolve(node.ofType, self.name)
    return self:generateTypeMap(node.ofType)
  end

  if self.typeMap[node.name] and self.typeMap[node.name] ~= node then
    error('Encountered multiple types named "' .. node.name .. '"')
  end

  node.fields = type(node.fields) == 'function' and node.fields() or node.fields
  self.typeMap[node.name] = node

  if node.__type == 'Object' and node.interfaces then
    for idx, interface in ipairs(node.interfaces) do
      -- BEGIN_HACK: resolve type names to real types
      if type(interface) == 'string' then
        interface = types.resolve(interface, self.name)
        node.interfaces[idx] = interface
      end
      -- END_HACK: resolve type names to real types

      self:generateTypeMap(interface)
      self.interfaceMap[interface.name] = self.interfaceMap[interface.name] or {}
      self.interfaceMap[interface.name][node] = node
    end
  end

  if node.__type == 'Object' or node.__type == 'Interface' or node.__type == 'InputObject' then
    for fieldName, field in pairs(node.fields) do
      if field.arguments then
        for name, argument in pairs(field.arguments) do
          -- BEGIN_HACK: resolve type names to real types
          if type(argument) == 'string' then
            argument = types.resolve(argument, self.name)
            field.arguments[name] = argument
          end

          if type(argument.kind) == 'string' then
            argument.kind = types.resolve(argument.kind, self.name)
          end
          -- END_HACK: resolve type names to real types

          local argumentType = argument.__type and argument or argument.kind
          assert(argumentType, 'Must supply type for argument "' .. name .. '" on "' .. fieldName .. '"')
          self:generateTypeMap(argumentType)
        end
      end

      -- HACK: resolve type names to real types
      field.kind = types.resolve(field.kind, self.name)
      self:generateTypeMap(field.kind)
    end
  end
end

function schema:generateDirectiveMap()
  for _, directive in ipairs(self.directives) do
    self.directiveMap[directive.name] = directive
    if directive.arguments ~= nil then
      for name, argument in pairs(directive.arguments) do

          -- BEGIN_HACK: resolve type names to real types
          if type(argument) == 'string' then
            argument = types.resolve(argument, self.name)
            directive.arguments[name] = argument
          end

          if type(argument.kind) == 'string' then
            argument.kind = types.resolve(argument.kind, self.name)
          end
          -- END_HACK: resolve type names to real types

          local argumentType = argument.__type and argument or argument.kind
          if argumentType == nil then
            error('Must supply type for argument "' .. name .. '" on "' .. directive.name .. '"')
          end
          self:generateTypeMap(argumentType)
      end
    end
  end
end

function schema:getType(name)
  if not name then return end
  return self.typeMap[name]
end

function schema:getImplementors(interface)
  local kind = self:getType(interface)
  local isInterface = kind and kind.__type == 'Interface'
  return self.interfaceMap[interface] or (isInterface and {} or nil)
end

function schema:getDirective(name)
  if not name then return false end
  return self.directiveMap[name]
end

function schema:getQueryType()
  return self.query
end

function schema:getMutationType()
  return self.mutation
end

function schema:getTypeMap()
  return self.typeMap
end

function schema:getPossibleTypes(abstractType)
  if abstractType.__type == 'Union' then
    return abstractType.types
  end

  return self:getImplementors(abstractType)
end

return schema
