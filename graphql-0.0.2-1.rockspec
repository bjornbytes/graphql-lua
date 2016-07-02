package = 'graphql'
version = '0.0.2-1'

source = {
  url = 'git://github.com/bjornbytes/graphql-lua.git'
}

description = {
  summary = 'Lua GraphQL implementation',
  homepage = 'https://github.com/bjornbytes/graphql-lua',
  maintainer = 'https://github.com/bjornbytes',
  license = 'MIT'
}

dependencies = {
  'lua >= 5.1',
  'lpeg'
}

build = {
  type = 'builtin',
  modules = {
    ['graphql'] = 'graphql/init.lua',
    ['graphql.parse'] = 'graphql/parse.lua',
    ['graphql.types'] = 'graphql/types.lua',
    ['graphql.introspection'] = 'graphql/introspection.lua',
    ['graphql.schema'] = 'graphql/schema.lua',
    ['graphql.validate'] = 'graphql/validate.lua',
    ['graphql.rules'] = 'graphql/rules.lua',
    ['graphql.execute'] = 'graphql/execute.lua',
    ['graphql.util'] = 'graphql/util.lua'
  }
}
