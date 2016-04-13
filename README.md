GraphQL Lua [![Join the chat at https://gitter.im/bjornbytes/graphql-lua](https://badges.gitter.im/bjornbytes/graphql-lua.svg)](https://gitter.im/bjornbytes/graphql-lua?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
===

Lua implementation of GraphQL.

Example
---

```lua
local parse = require 'graphql.parse'
local schema = require 'graphql.schema'
local types = require 'graphql.types'
local validate = require 'graphql.validate'
local execute = require 'graphql.execute'

-- Parse a query
local ast = parse [[
query getUser($id: ID) {
  person(id: $id) {
    firstName
    lastName
  }
}
]]

-- Create a type
local Person = types.object {
  name = 'Person',
  fields = {
    id = types.id.nonNull,
    firstName = types.string.nonNull,
    middleName = types.string,
    lastName = types.string.nonNull,
    age = types.int.nonNull
  }
}

-- Create a schema
local schema = schema.create {
  query = types.object {
    name = 'Query',
    fields = {
      person = {
        kind = Person,
        arguments = {
          id = types.id
        },
        resolve = function(rootValue, arguments)
          if arguments.id ~= 1 then return nil end

          return {
            id = 1,
            firstName = 'Bob',
            lastName = 'Ross',
            age = 52
          }
        end
      }
    }
  }
}

-- Validate a parsed query against a schema
validate(schema, ast)

-- Execution
local rootValue = {}
local variables = { id = 1 }
local operationName = 'getUser'

execute(schema, ast, rootValue, variables, operationName)

--[[
{
  person = {
    firstName = 'Bob',
    lastName = 'Ross'
  }
}
]]
```

Status
---

- [x] Parsing
  - [ ] Improve error messages
- [x] Type system
- [ ] Introspection
- [x] Validation
- [x] Execution
  - [ ] Asynchronous execution (coroutines)
- [ ] Example server

Running tests
---

```lua
lua tests/runner.lua
```

License
---

MIT
