local schema = {}
schema.__index = schema

function schema.create(config)
  assert(type(config.query) == 'table', 'must provide query object')

  local self = {}
  for k, v in pairs(config) do
    self[k] = v
  end

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
        print(require('inspect')(interface))
        generateTypeMap(interface)
      end
    end

    if node.__type == 'Object' or node.__type == 'Interface' or node.__type == 'Union' then
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

  self.typeMap = {}

  generateTypeMap(self.query)

  return setmetatable(self, schema)
end

function schema:getType(name)
  return self.typeMap[name]
end

return schema
