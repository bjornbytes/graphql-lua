local schema = {}
schema.__index = schema

function schema.create(config)
  assert(type(config.query) == 'table', 'must provide query object')

  local self = {}
  for k, v in pairs(config) do
    self[k] = v
  end

  self.typeMap = {}
  self.interfaceMap = {}

  local function generateTypeMap(node)
    if node.__type == 'NonNull' or node.__type == 'List' then
      return generateTypeMap(node.ofType)
    end

    if self.typeMap[node.name] and self.typeMap[node.name] ~= node then
      error('Encountered multiple types named "' .. node.name .. '"')
    end

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
          for _, argument in pairs(field.arguments) do
            generateTypeMap(argument)
          end
        end

        generateTypeMap(field.kind)
      end
    end
  end

  generateTypeMap(self.query)

  return setmetatable(self, schema)
end

function schema:getType(name)
  return self.typeMap[name]
end

function schema:getImplementors(interface)
  local kind = self:getType(interface)
  local isInterface = kind and kind.__type == 'Interface'
  return self.interfaceMap[interface] or (isInterface and {} or nil)
end

return schema
