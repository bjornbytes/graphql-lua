local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local introspection = require(path .. '.introspection')

local schema = {}
schema.__index = schema

function schema.create(config)
  assert(type(config.query) == 'table', 'must provide query object')
  assert(not config.mutation or type(config.mutation) == 'table', 'mutation must be a table if provided')

  local self = setmetatable({}, schema)

  for k, v in pairs(config) do
    self[k] = v
  end

  self.directives = self.directives or {
    types.include,
    types.skip
  }

  self.typeMap = {}
  self.interfaceMap = {}
  self.directiveMap = {}

  self:generateTypeMap(self.query)
  self:generateTypeMap(self.mutation)
  self:generateTypeMap(introspection.__Schema)
  self:generateDirectiveMap()

  return self
end

function schema:generateTypeMap(node)
  if not node or (self.typeMap[node.name] and self.typeMap[node.name] == node) then return end

  if node.__type == 'NonNull' or node.__type == 'List' then
    return self:generateTypeMap(node.ofType)
  end

  if self.typeMap[node.name] and self.typeMap[node.name] ~= node then
    error('Encountered multiple types named "' .. node.name .. '"')
  end

  node.fields = type(node.fields) == 'function' and node.fields() or node.fields
  self.typeMap[node.name] = node

  if node.__type == 'Object' and node.interfaces then
    for _, interface in ipairs(node.interfaces) do
      self:generateTypeMap(interface)
      self.interfaceMap[interface.name] = self.interfaceMap[interface.name] or {}
      self.interfaceMap[interface.name][node] = node
    end
  end

  if node.__type == 'Object' or node.__type == 'Interface' or node.__type == 'InputObject' then
    for fieldName, field in pairs(node.fields) do
      if field.arguments then
        for name, argument in pairs(field.arguments) do
          local argumentType = argument.__type and argument or argument.kind
          assert(argumentType, 'Must supply type for argument "' .. name .. '" on "' .. fieldName .. '"')
          self:generateTypeMap(argumentType)
        end
      end

      self:generateTypeMap(field.kind)
    end
  end
end

function schema:generateDirectiveMap()
  for _, directive in ipairs(self.directives) do
    self.directiveMap[directive.name] = directive
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
