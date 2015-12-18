GraphQL Lua
===

Lua implementation of GraphQL parser using LPeg.  Experimental.

API
---

Parsing queries:

```lua
local parse = require 'parse'
local ast = parse [[
query getUser {
  firstName
  lastName
}
]]
```

Creating schemas:

```lua
local schema = require 'schema'
local types = require 'types'

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
local validate = require 'validate'
validate(schema, ast)
```

Running tests
---

```lua
lua tests/runner.lua
```

License
---

MIT
