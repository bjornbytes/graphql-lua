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

Status
---

The parser can parse virtually all of the query syntax:

- Documents
- Definitions
  - OperationDefinition
  - FragmentDefinition
- Selections
- Fields
- Aliases
- Arguments
- FragmentSpreads and InlineFragments
- All value types (scalars, enums, lists, objects, variables).
- VariableDefinitions (typed)
- Directives

The type system supports scalars, objects, enums, interfaces, and unions.  The built in scalars are
also provided (ints, floats, strings, etc.).

License
---

MIT
