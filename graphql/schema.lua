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

  self.typeMap = {}

  self.interfaceMap = {}
  self.directiveMap = {}

  local function generateTypeMap(node)
    if not node or (self.typeMap[node.name] and self.typeMap[node.name] == node) then return end

    if node.__type == 'NonNull' or node.__type == 'List' then
      return generateTypeMap(node.ofType)
    end

    if self.typeMap[node.name] and self.typeMap[node.name] ~= node then
      error('Encountered multiple types named "' .. node.name .. '"')
    end

    if type(node.fields) == 'function' then node.fields = node.fields() end
    self.typeMap[node.name] = node

    if node.__type == 'Object' and node.interfaces then
      for _, interface in ipairs(node.interfaces) do
        generateTypeMap(interface)
        self.interfaceMap[interface.name] = self.interfaceMap[interface.name] or {}
        self.interfaceMap[interface.name][node] = node
      end
    end

    if node.__type == 'Object' or node.__type == 'Interface' or node.__type == 'InputObject' then
      for fieldName, field in pairs(node.fields) do
        if field.arguments then
          for k, argument in pairs(field.arguments) do
            if argument.__type
            then generateTypeMap(argument)
            else
              assert(type(argument.kind) == 'table', 'kind of argument "'.. k ..'" for "' .. fieldName .. '" must be supplied')
              generateTypeMap(argument.kind)
            end
          end
        end
        generateTypeMap(field.kind)
      end
    end
  end

  generateTypeMap(self.query)
  generateTypeMap(self.mutation)
  generateTypeMap(introspection.__Schema)

  self.directives = self.directives or {
    types.include,
    types.skip
  }

  if self.directives then
    for _, directive in ipairs(self.directives) do
      self.directiveMap[directive.name] = directive
    end
  end

  return self
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

function schema.getParentField(context, name, count)
  if name == '__schema' then
    return introspection.SchemaMetaFieldDef
  elseif name == '__type' then
    return introspection.TypeMetaFieldDef
  elseif name == '__typename' then
    return introspection.TypeNameMetaFieldDef
  end

  count = count or 1
  local parent = context.objects[#context.objects - count]

  -- Unwrap lists and non-null types
  while parent.ofType do
    parent = parent.ofType
  end

  return parent.fields[name]
end

return schema
