package = 'graphql'
version = 'scm-1'

source = {
  url = 'git://github.com/tarantool/graphql.git'
}

description = {
  summary = 'GraphQL implementation for Tarantool',
  homepage = 'https://github.com/tarantool/graphql',
  maintainer = 'https://github.com/tarantool',
  license = 'MIT'
}

dependencies = {
  'lua >= 5.1',
  'lulpeg',
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
