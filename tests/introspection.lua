local parse = require 'graphql.parse'
local validate = require 'graphql.validate'
local execute = require 'graphql.execute'
local util = require 'graphql.util'
local cjson = require 'cjson'
local schema = require 'tests/data/todo'

local introspection_query = [[
  query IntrospectionQuery {
    __schema {
      queryType { name }
      mutationType { name }
      types {
        ...FullType
      }
      directives {
        name
        description
        locations
        args {
          ...InputValue
        }
      }
    }
  }

  fragment FullType on __Type {
    kind
    name
    description
    fields(includeDeprecated: true) {
      name
      description
      args {
        ...InputValue
      }
      type {
        ...TypeRef
      }
      isDeprecated
      deprecationReason
    }
    inputFields {
      ...InputValue
    }
    interfaces {
      ...TypeRef
    }
    enumValues(includeDeprecated: true) {
      name
      description
      isDeprecated
      deprecationReason
    }
    possibleTypes {
      ...TypeRef
    }
  }

  fragment InputValue on __InputValue {
    name
    description
    type { ...TypeRef }
    defaultValue
  }

  fragment TypeRef on __Type {
    kind
    name
    ofType {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
      }
    }
  }
]]
local introspection_expected_json = [[
  {
    "__schema": {
      "directives": [
        {
          "args": [
            {
              "defaultValue": null,
              "description": "Included when true.",
              "name": "if",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            }
          ],
          "description": "Directs the executor to include this field or fragment only when the `if` argument is true.",
          "locations": [
            "FIELD",
            "FRAGMENT_SPREAD",
            "INLINE_FRAGMENT"
          ],
          "name": "include"
        },
        {
          "args": [
            {
              "defaultValue": null,
              "description": "Skipped when true.",
              "name": "if",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            }
          ],
          "description": "Directs the executor to skip this field or fragment when the `if` argument is true.",
          "locations": [
            "FIELD",
            "FRAGMENT_SPREAD",
            "INLINE_FRAGMENT"
          ],
          "name": "skip"
        }
      ],
      "mutationType": null,
      "queryType": {
        "name": "Query"
      },
      "types": [
        {
          "description": null,
          "enumValues": null,
          "fields": [
            {
              "args": [
                {
                  "defaultValue": null,
                  "description": "id of the client",
                  "name": "id",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Int",
                      "ofType": null
                    }
                  }
                }
              ],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "client",
              "type": {
                "kind": "OBJECT",
                "name": "Client",
                "ofType": null
              }
            },
            {
              "args": [
                {
                  "defaultValue": null,
                  "description": "id of the project",
                  "name": "id",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Int",
                      "ofType": null
                    }
                  }
                }
              ],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "project",
              "type": {
                "kind": "OBJECT",
                "name": "Project",
                "ofType": null
              }
            },
            {
              "args": [
                {
                  "defaultValue": null,
                  "description": "id of the task",
                  "name": "id",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Int",
                      "ofType": null
                    }
                  }
                }
              ],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "task",
              "type": {
                "kind": "OBJECT",
                "name": "Task",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "Query",
          "possibleTypes": null
        },
        {
          "description": "The `Int` scalar type represents non-fractional signed whole numeric values. Int can represent values between -(2^31) and 2^31 - 1. ",
          "enumValues": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "kind": "SCALAR",
          "name": "Int",
          "possibleTypes": null
        },
        {
          "description": "Client",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": "The id of the client.",
              "isDeprecated": false,
              "name": "id",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Int",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "The name of the client.",
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "projects",
              "isDeprecated": false,
              "name": "projects",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Project",
                  "ofType": null
                }
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "Client",
          "possibleTypes": null
        },
        {
          "description": "The `String` scalar type represents textual data, represented as UTF-8 character sequences. The String type is most often used by GraphQL to represent free-form human-readable text.",
          "enumValues": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "kind": "SCALAR",
          "name": "String",
          "possibleTypes": null
        },
        {
          "description": "Project",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": "The id of the project.",
              "isDeprecated": false,
              "name": "id",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Int",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "The name of the project.",
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "client id",
              "isDeprecated": false,
              "name": "client_id",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Int",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "client",
              "isDeprecated": false,
              "name": "client",
              "type": {
                "kind": "OBJECT",
                "name": "Client",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "tasks",
              "isDeprecated": false,
              "name": "tasks",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Task",
                  "ofType": null
                }
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "Project",
          "possibleTypes": null
        },
        {
          "description": "Task",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": "The id of the task.",
              "isDeprecated": false,
              "name": "id",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Int",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "The name of the task.",
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "project id",
              "isDeprecated": false,
              "name": "project_id",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Int",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "project",
              "isDeprecated": false,
              "name": "project",
              "type": {
                "kind": "OBJECT",
                "name": "Project",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "Task",
          "possibleTypes": null
        },
        {
          "description": "A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query and mutation operations.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": "A list of all types supported by this server.",
              "isDeprecated": false,
              "name": "types",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Type",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "The type that query operations will be rooted at.",
              "isDeprecated": false,
              "name": "queryType",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "If this server supports mutation, the type that mutation operations will be rooted at.",
              "isDeprecated": false,
              "name": "mutationType",
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "A list of all directives supported by this server.",
              "isDeprecated": false,
              "name": "directives",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Directive",
                      "ofType": null
                    }
                  }
                }
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__Schema",
          "possibleTypes": null
        },
        {
          "description": "The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.\n\nDepending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name and description, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "kind",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "ENUM",
                  "name": "__TypeKind",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "description",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [
                {
                  "defaultValue": "false",
                  "description": null,
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "fields",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Field",
                    "ofType": null
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "interfaces",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "possibleTypes",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "args": [
                {
                  "defaultValue": "false",
                  "description": null,
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "enumValues",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__EnumValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "inputFields",
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__InputValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "ofType",
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__Type",
          "possibleTypes": null
        },
        {
          "description": "An enum describing what kind of type a given `__Type` is.",
          "enumValues": [
            {
              "deprecationReason": null,
              "description": "Indicates this type is a scalar.",
              "isDeprecated": false,
              "name": "SCALAR"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is an object. `fields` and `interfaces` are valid fields.",
              "isDeprecated": false,
              "name": "OBJECT"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is an interface. `fields` and `possibleTypes` are valid fields.",
              "isDeprecated": false,
              "name": "INTERFACE"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is a union. `possibleTypes` is a valid field.",
              "isDeprecated": false,
              "name": "UNION"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is an enum. `enumValues` is a valid field.",
              "isDeprecated": false,
              "name": "ENUM"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is an input object. `inputFields` is a valid field.",
              "isDeprecated": false,
              "name": "INPUT_OBJECT"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is a list. `ofType` is a valid field.",
              "isDeprecated": false,
              "name": "LIST"
            },
            {
              "deprecationReason": null,
              "description": "Indicates this type is a non-null. `ofType` is a valid field.",
              "isDeprecated": false,
              "name": "NON_NULL"
            }
          ],
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "kind": "ENUM",
          "name": "__TypeKind",
          "possibleTypes": null
        },
        {
          "description": "The `Boolean` scalar type represents `true` or `false`.",
          "enumValues": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "kind": "SCALAR",
          "name": "Boolean",
          "possibleTypes": null
        },
        {
          "description": "Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "description",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "args",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "type",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "isDeprecated",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "deprecationReason",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__Field",
          "possibleTypes": null
        },
        {
          "description": "Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "description",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "type",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": "A GraphQL-formatted string representing the default value for this input value.",
              "isDeprecated": false,
              "name": "defaultValue",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__InputValue",
          "possibleTypes": null
        },
        {
          "description": "One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "description",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "isDeprecated",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "deprecationReason",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__EnumValue",
          "possibleTypes": null
        },
        {
          "description": "A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.\n\nIn some cases, you need to provide options to alter GraphQL’s execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.",
          "enumValues": null,
          "fields": [
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "name",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "description",
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "locations",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "ENUM",
                      "name": "__DirectiveLocation",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": null,
              "description": null,
              "isDeprecated": false,
              "name": "args",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "args": [],
              "deprecationReason": "Use `locations`.",
              "description": null,
              "isDeprecated": true,
              "name": "onOperation",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": "Use `locations`.",
              "description": null,
              "isDeprecated": true,
              "name": "onFragment",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "args": [],
              "deprecationReason": "Use `locations`.",
              "description": null,
              "isDeprecated": true,
              "name": "onField",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "kind": "OBJECT",
          "name": "__Directive",
          "possibleTypes": null
        },
        {
          "description": "A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.",
          "enumValues": [
            {
              "deprecationReason": null,
              "description": "Location adjacent to a query operation.",
              "isDeprecated": false,
              "name": "QUERY"
            },
            {
              "deprecationReason": null,
              "description": "Location adjacent to a mutation operation.",
              "isDeprecated": false,
              "name": "MUTATION"
            },
            {
              "deprecationReason": null,
              "description": "Location adjacent to a field.",
              "isDeprecated": false,
              "name": "FIELD"
            },
            {
              "deprecationReason": null,
              "description": "Location adjacent to a fragment definition.",
              "isDeprecated": false,
              "name": "FRAGMENT_DEFINITION"
            },
            {
              "deprecationReason": null,
              "description": "Location adjacent to a fragment spread.",
              "isDeprecated": false,
              "name": "FRAGMENT_SPREAD"
            },
            {
              "deprecationReason": null,
              "description": "Location adjacent to an inline fragment.",
              "isDeprecated": false,
              "name": "INLINE_FRAGMENT"
            }
          ],
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "kind": "ENUM",
          "name": "__DirectiveLocation",
          "possibleTypes": null
        }
      ]
    }
  }
]]

describe('introspection', function()
  local rootValue = {}
  local variables = {}
  local operationName = 'IntrospectionQuery'
  local response = execute(schema, parse(introspection_query), rootValue, variables, operationName)
  local expected = cjson.decode(introspection_expected_json)
  assert:set_parameter("TableFormatLevel", 10) 
  local compare_by_name = function(a,b) return a.name < b.name end  
  table.sort(response.__schema.directives, compare_by_name)
  table.sort(expected.__schema.directives, compare_by_name)
  table.sort(response.__schema.types, compare_by_name)
  table.sort(expected.__schema.types, compare_by_name)
  for i,v in ipairs(expected.__schema.types) do
    if v.fields ~= cjson.null then table.sort(v.fields, compare_by_name) end
    if v.enumValues ~= cjson.null then table.sort(v.enumValues, compare_by_name) end
  end
  for i,v in ipairs(response.__schema.types) do
    if v.fields ~= cjson.null then table.sort(v.fields, compare_by_name) end
    if v.enumValues ~= cjson.null then table.sort(v.enumValues, compare_by_name) end
  end

  it('basic json equality test', function()
      assert.are.same(cjson.decode('{"a":1,    "b":2}'),{b = 2, a = 1})
  end)

  it('root nodes are set', function()
      assert.is.truthy(response.__schema)
      assert.is.truthy(response.__schema.directives)
      assert.is.truthy(response.__schema.mutationType)
      assert.is.truthy(response.__schema.queryType)
      assert.is.truthy(response.__schema.types)
  end)

  it('mutationType match', function()
    assert.are.same(expected.__schema.mutationType, response.__schema.mutationType)
  end)

  it('queryType match', function()
    assert.are.same(expected.__schema.queryType, response.__schema.queryType)
  end)

  it('root types are same', function()
    local expected = util.map(expected.__schema.types, function ( t ) return t.name end)
    local response = util.map(response.__schema.types, function ( t ) return t.name end)
    table.sort(expected)
    table.sort(response)
    assert.are.same(expected, response)
  end)

  it('types match', function()
    assert.are.same(expected.__schema.types, response.__schema.types)
  end)

  it('directives match', function()
    assert.are.same(expected.__schema.directives, response.__schema.directives)
  end)

  it('all match', function()
    assert.are.same(expected, response)
  end)

end)
