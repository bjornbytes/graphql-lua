GraphQL Lua
===

Lua implementation of GraphQL.

API
---

Parsing queries:

```lua
local parse = require 'graphql.parse'
local ast = parse [[
query getUser {
  firstName
  lastName
}
]]
```

Creating schemas:

```lua
local schema = require 'graphql.schema'
local types = require 'graphql.types'

local person = types.object {
  name = 'Person',
  fields = {
    firstName = types.string.nonNull
    lastName = types.string.nonNull
  }
}

local schema = schema.create {
  query = types.object {
    name = 'Query',
    fields = {
      person = person
    }
  }
}
```

Validating schemas:

```lua
local validate = require 'graphql.validate'
validate(schema, ast)
```

Executing queries:

```lua
local execute = require 'graphql.execute'
local rootValue = {}
local variables = {
  foo = 'bar'
}
local operationName = 'myOperation'

execute(schema, ast, rootValue, variables, operationName)
```

Running tests
---

```lua
lua tests/runner.lua
```

License
---

MIT
