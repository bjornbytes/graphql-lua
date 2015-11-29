GraphQL Lua
===

Lua implementation of GraphQL parser using LPeg.  Experimental.

Example
---

```lua
require 'parse' [[{
  me {
    firstName
    lastName
  }
}]]
```

Gives you this scary table:

```lua
{
  kind = "document",
  definitions = {
    {
      kind = "operation",
      operation = "query",
      selectionSet = {
        kind = "selectionSet",
        selections = {
          {
            kind = "field",
            name = {
              kind = "name",
              value = "me"
            },
            selectionSet = {
              kind = "selectionSet",
              selections = {
                {
                  kind = "field",
                  name = {
                    kind = "name",
                    value = "firstName"
                  }
                },
                {
                  kind = "field",
                  name = {
                    kind = "name",
                    value = "lastName"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

License
---

MIT
