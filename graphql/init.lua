local path = (...):gsub('%.init$', '')

local graphql = {}

graphql.parse = require(path .. '.parse')
graphql.types = require(path .. '.types')
graphql.schema = require(path .. '.schema')
graphql.validate = require(path .. '.validate')
graphql.execute = require(path .. '.execute')

return graphql
