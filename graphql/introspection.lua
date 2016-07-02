local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')

local __Schema, __Directive, __DirectiveLocation, __Type, __Field, __InputValue,__EnumValue, __TypeKind

__Schema = types.object({
  name = '__Schema',

  description = util.trim [[
    A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types
    and directives on the server, as well as the entry points for query and mutation operations.
  ]],

  fields = function()
    return {
      types = {
        description = 'A list of all types supported by this server.',
        kind = types.nonNull(types.list(types.nonNull(__Type))),
        resolve = function(schema)
          return util.values(schema:getTypeMap())
        end
      },

      queryType = {
        description = 'The type that query operations will be rooted at.',
        kind = __Type.nonNull,
        resolve = function(schema)
          return schema:getQueryType()
        end
      },

      mutationType = {
        description = 'If this server supports mutation, the type that mutation operations will be rooted at.',
        kind = __Type,
        resolve = function(schema)
          return schema:getMutationType()
        end
      },

      directives = {
        description = 'A list of all directives supported by this server.',
        kind = types.nonNull(types.list(types.nonNull(__Directive))),
        resolve = function(schema)
          return schema.directives
        end
      }
    }
  end
})

__Directive = types.object({
  name = '__Directive',

  description = util.trim [[
    A Directive provides a way to describe alternate runtime execution and type validation behavior
    in a GraphQL document.

    In some cases, you need to provide options to alter GraphQL’s execution
    behavior in ways field arguments will not suffice, such as conditionally including or skipping a
    field. Directives provide this by describing additional information to the executor.
  ]],

  fields = function()
    return {
      name = types.nonNull(types.string),

      description = types.string,

      locations = {
        kind = types.nonNull(types.list(types.nonNull(
          __DirectiveLocation
        ))),
        resolve = function(directive)
          local res = {}

          if directive.onQuery then table.insert(res, 'QUERY') end
          if directive.onMutation then table.insert(res, 'MUTATION') end
          if directive.onField then table.insert(res, 'FIELD') end
          if directive.onFragmentDefinition then table.insert(res, 'FRAGMENT_DEFINITION') end
          if directive.onFragmentSpread then table.insert(res, 'FRAGMENT_SPREAD') end
          if directive.onInlineFragment then table.insert(res, 'INLINE_FRAGMENT') end

          return res
        end
      },

      args = {
        kind = types.nonNull(types.list(types.nonNull(__InputValue))),
        resolve = function(field)
          local args = {}
          local transform = function(a, n)
            if a.__type then
              return { kind = a, name = n }
            else
              if a.name then return a end

              local r = { name = n }
              for k,v in pairs(a) do
                r[k] = v
              end

              return r
            end
          end

          for k, v in pairs(field.arguments or {}) do
            table.insert(args, transform(v, k))
          end

          return args
        end
      }
    }
  end
})

__DirectiveLocation = types.enum({
  name = '__DirectiveLocation',

  description = util.trim [[
    A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation
    describes one such possible adjacencies.
  ]],

  values = {
    QUERY = {
      value = 'QUERY',
      description = 'Location adjacent to a query operation.'
    },

    MUTATION = {
      value = 'MUTATION',
      description = 'Location adjacent to a mutation operation.'
    },

    FIELD = {
      value = 'FIELD',
      description = 'Location adjacent to a field.'
    },

    FRAGMENT_DEFINITION = {
      value = 'FRAGMENT_DEFINITION',
      description = 'Location adjacent to a fragment definition.'
    },

    FRAGMENT_SPREAD = {
      value = 'FRAGMENT_SPREAD',
      description = 'Location adjacent to a fragment spread.'
    },

    INLINE_FRAGMENT = {
      value = 'INLINE_FRAGMENT',
      description = 'Location adjacent to an inline fragment.'
    }
  }
})

__Type = types.object({
  name = '__Type',

  description = util.trim [[
    The fundamental unit of any GraphQL Schema is the type. There are
    many kinds of types in GraphQL as represented by the `__TypeKind` enum.

    Depending on the kind of a type, certain fields describe
    information about that type. Scalar types provide no information
    beyond a name and description, while Enum types provide their values.
    Object and Interface types provide the fields they describe. Abstract
    types, Union and Interface, provide the Object types possible
    at runtime. List and NonNull types compose other types.
  ]],

  fields = function()
    return {
      name = types.string,
      description = types.string,

      kind = {
        kind = __TypeKind.nonNull,
        resolve = function(kind)
          if kind.__type == 'Scalar' then
            return 'SCALAR'
          elseif kind.__type == 'Object' then
            return 'OBJECT'
          elseif kind.__type == 'Interface' then
            return 'INTERFACE'
          elseif kind.__type == 'Union' then
            return 'UNION'
          elseif kind.__type == 'Enum' then
            return 'ENUM'
          elseif kind.__type == 'InputObject' then
            return 'INPUT_OBJECT'
          elseif kind.__type == 'List' then
            return 'LIST'
          elseif kind.__type == 'NonNull' then
            return 'NON_NULL'
          end

          error('Unknown type ' .. kind)
        end
      },

      fields = {
        kind = types.list(types.nonNull(__Field)),
        arguments = {
          includeDeprecated = {
            kind = types.boolean,
            defaultValue = false
          }
        },
        resolve = function(kind, arguments)
          if kind.__type == 'Object' or kind.__type == 'Interface' then
            return util.filter(util.values(kind.fields), function(field)
              return arguments.includeDeprecated or field.deprecationReason == nil
            end)
          end

          return nil
        end
      },

      interfaces = {
        kind = types.list(types.nonNull(__Type)),
        resolve = function(kind)
          if kind.__type == 'Object' then
            return kind.interfaces
          end
        end
      },

      possibleTypes = {
        kind = types.list(types.nonNull(__Type)),
        resolve = function(kind, arguments, context)
          if kind.__type == 'Interface' or kind.__type == 'Union' then
            return context.schema:getPossibleTypes(kind)
          end
        end
      },

      enumValues = {
        kind = types.list(types.nonNull(__EnumValue)),
        arguments = {
          includeDeprecated = { kind = types.boolean, defaultValue = false }
        },
        resolve = function(kind, arguments)
          if kind.__type == 'Enum' then
            return util.filter(util.values(kind.values), function(value)
              return arguments.includeDeprecated or not value.deprecationReason
            end)
          end
        end
      },

      inputFields = {
        kind = types.list(types.nonNull(__InputValue)),
        resolve = function(kind)
          if kind.__type == 'InputObject' then
            return util.values(kind.fields)
          end
        end
      },

      ofType = {
        kind = __Type
      }
    }
  end
})

__Field = types.object({
  name = '__Field',

  description = util.trim [[
    Object and Interface types are described by a list of Fields, each of
    which has a name, potentially a list of arguments, and a return type.
  ]],

  fields = function()
    return {
      name = types.string.nonNull,
      description = types.string,

      args = {
        -- kind = types.list(__InputValue),
        kind = types.nonNull(types.list(types.nonNull(__InputValue))),
        resolve = function(field)
          return util.map(field.arguments or {}, function(a, n)
            if a.__type then
              return { kind = a, name = n }
            else
              if not a.name then
                local r = { name = n }

                for k,v in pairs(a) do
                  r[k] = v
                end

                return r
              else
                return a
              end
            end
          end)
        end
      },

      type = {
        kind = __Type.nonNull,
        resolve = function(field)
          return field.kind
        end
      },

      isDeprecated = {
        kind = types.boolean.nonNull,
        resolve = function(field)
          return field.deprecationReason ~= nil
        end
      },

      deprecationReason = types.string
    }
  end
})

__InputValue = types.object({
  name = '__InputValue',

  description = util.trim [[
    Arguments provided to Fields or Directives and the input fields of an
    InputObject are represented as Input Values which describe their type
    and optionally a default value.
  ]],

  fields = function()
    return {
      name = types.string.nonNull,
      description = types.string,

      type = {
        kind = types.nonNull(__Type),
        resolve = function(field)
          return field.kind
        end
      },

      defaultValue = {
        kind = types.string,
        description = 'A GraphQL-formatted string representing the default value for this input value.',
        resolve = function(inputVal)
          return inputVal.defaultValue and tostring(inputVal.defaultValue) -- TODO improve serialization a lot
        end
      }
    }
  end
})

__EnumValue = types.object({
  name = '__EnumValue',

  description = [[
    One possible value for a given Enum. Enum values are unique values, not
    a placeholder for a string or numeric value. However an Enum value is
    returned in a JSON response as a string.
  ]],

  fields = function()
    return {
      name = types.string.nonNull,
      description = types.string,
      isDeprecated = {
        kind = types.boolean.nonNull,
        resolve = function(enumValue) return enumValue.deprecationReason ~= nil end
      },
      deprecationReason = types.string
    }
  end
})

__TypeKind = types.enum({
  name = '__TypeKind',
  description = 'An enum describing what kind of type a given `__Type` is.',
  values = {
    SCALAR = {
      value = 'SCALAR',
      description = 'Indicates this type is a scalar.'
    },

    OBJECT = {
      value = 'OBJECT',
      description = 'Indicates this type is an object. `fields` and `interfaces` are valid fields.'
    },

    INTERFACE = {
      value = 'INTERFACE',
      description = 'Indicates this type is an interface. `fields` and `possibleTypes` are valid fields.'
    },

    UNION = {
      value = 'UNION',
      description = 'Indicates this type is a union. `possibleTypes` is a valid field.'
    },

    ENUM = {
      value = 'ENUM',
      description = 'Indicates this type is an enum. `enumValues` is a valid field.'
    },

    INPUT_OBJECT = {
      value = 'INPUT_OBJECT',
      description = 'Indicates this type is an input object. `inputFields` is a valid field.'
    },

    LIST = {
      value = 'LIST',
      description = 'Indicates this type is a list. `ofType` is a valid field.'
    },

    NON_NULL = {
      value = 'NON_NULL',
      description = 'Indicates this type is a non-null. `ofType` is a valid field.'
    }
  }
})

local Schema = {
  name = '__schema',
  kind = __Schema.nonNull,
  description = 'Access the current type schema of this server.',
  arguments = {},
  resolve = function(_, _, info)
    return info.schema
  end
}

local Type = {
  name = '__type',
  kind = __Type,
  description = 'Request the type information of a single type.',
  arguments = {
    name = types.string.nonNull
  },
  resolve = function(_, arguments, info)
    return info.schema:getType(arguments.name)
  end
}

local TypeName = {
  name = '__typename',
  kind = types.string.nonNull,
  description = 'The name of the current Object type at runtime.',
  arguments = {},
  resolve = function(_, _, info)
    return info.parentType.name
  end
}

return {
  __Schema = __Schema,
  __Directive = __Directive,
  __DirectiveLocation = __DirectiveLocation,
  __Type = __Type,
  __Field = __Field,
  __EnumValue = __EnumValue,
  __TypeKind = __TypeKind,
  Schema = Schema,
  Type = Type,
  TypeName = TypeName,
  fieldMap = {
    __schema = Schema,
    __type = Type,
    __typename = TypeName
  }
}
