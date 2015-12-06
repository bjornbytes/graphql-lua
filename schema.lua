local schema = {}
schema.__index = schema

function schema.create(config)
  assert(type(config.query) == 'table', 'must provide query object')

  return config
end

return schema
