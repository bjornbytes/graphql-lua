local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')
local cjson = require 'cjson' -- needs to be cloned from here https://github.com/openresty/lua-cjson for cjson.empty_array feature

local function instanceof(t, s)
  return t.__type == s
end

local function trim(s)
  return s:gsub('^%s+', ''):gsub('%s$', ''):gsub('%s%s+', ' ')
end

local __Directive, __DirectiveLocation, __Type, __Field, __InputValue,__EnumValue, __TypeKind, SchemaMetaFieldDef, TypeMetaFieldDef, TypeNameMetaFieldDef, astFromValue, printAst, printers

local __Schema = types.object({
  name = '__Schema',

  description = trim [[
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

  description = trim [[
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
        )))
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

          if #args > 0 then
            return args
          else
            return cjson.empty_array
          end
        end
      }
    }
  end
})

__DirectiveLocation = types.enum({
  name = '__DirectiveLocation',

  description = trim [[
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

  description = trim [[
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
        resolve = function(type)
          if instanceof(type, 'Scalar') then
            return 'SCALAR'
          elseif instanceof(type, 'Object') then
            return 'OBJECT'
          elseif instanceof(type, 'Interface') then
            return 'INTERFACE'
          elseif instanceof(type, 'Union') then
            return 'UNION'
          elseif instanceof(type, 'Enum') then
            return 'ENUM'
          elseif instanceof(type, 'InputObject') then
            return 'INPUT_OBJECT'
          elseif instanceof(type, 'List') then
            return 'LIST'
          elseif instanceof(type, 'NonNull') then
            return 'NON_NULL'
          end

          error('Unknown kind of kind = ' .. type)
        end
      },

      fields = {
        kind = types.list(types.nonNull(__Field)),
        arguments = {
          includeDeprecated = { kind = types.boolean, defaultValue = false }
        },
        resolve = function(type, arguments)
          if instanceof(type, 'Object') or instanceof(type, 'Interface') then
            return util.filter(util.values(type.fields), function(field)
              return arguments.includeDeprecated or field.deprecationReason == nil
            end)
          end

          return nil
        end
      },

      interfaces = {
        kind = types.list(types.nonNull(__Type)),
        resolve = function(type)
          if instanceof(type, 'Object') then
            return type.interfaces
          end
        end
      },

      possibleTypes = {
        kind = types.list(types.nonNull(__Type)),
        resolve = function(type, arguments, context)
          if instanceof(type, 'Interface') or instanceof(type, 'Union') then
            return context.schema:getPossibleTypes(type)
          end
        end
      },

      enumValues = {
        kind = types.list(types.nonNull(__EnumValue)),
        arguments = {
          includeDeprecated = { kind = types.boolean, defaultValue = false }
        },
        resolve = function(type, arguments)
          if instanceof(type, 'Enum') then
            return util.filter(util.values(type.values), function(value)
              return arguments.includeDeprecated or not value.deprecationReason
            end)
          end
        end
      },

      inputFields = {
        kind = types.list(types.nonNull(__InputValue)),
        resolve = function(type)
          if instanceof(type, 'InputObject') then
            return util.values(type.fields)
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

  description = trim [[
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

  description = trim [[
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
          return inputVal.defaultValue and printAst(astFromValue(inputVal.defaultValue, inputVal)) or nil
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

--
-- Note that these are GraphQLFieldDefinition and not GraphQLFieldConfig,
-- so the format for args is different.
--

SchemaMetaFieldDef = {
  name = '__schema',
  kind = __Schema.nonNull,
  description = 'Access the current type schema of this server.',
  arguments = {},
  resolve = function(_, _, info)
    return info.schema
  end
}

TypeMetaFieldDef = {
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

TypeNameMetaFieldDef = {
  name = '__typename',
  kind = types.string.nonNull,
  description = 'The name of the current Object type at runtime.',
  arguments = {},
  resolve = function(_, _, info)
    return info.parentType.name
  end
}

-- Produces a GraphQL Value AST given a lua value.

-- Optionally, a GraphQL type may be provided, which will be used to
-- disambiguate between value primitives.

-- | JSON Value    | GraphQL Value        |
-- | ------------- | -------------------- |
-- | Object        | Input Object         |
-- | Array         | List                 |
-- | Boolean       | Boolean              |
-- | String        | String / Enum Value  |
-- | Number        | Int / Float          |

local Kind = {
  LIST = 'ListValue',
  BOOLEAN = 'BooleanValue',
  FLOAT = 'FloatValue',
  INT = 'IntValue',
  FLOAT = 'FloatValue',
  ENUM = 'EnumValue',
  STRING = 'StringValue',
  OBJECT_FIELD = 'ObjectField',
  NAME = 'Name',
  OBJECT = 'ObjectValue'
}

printers = {
  IntValue = function(v) return v.value end,
  FloatValue = function(v) return v.value end,
  StringValue = function(v) return cjson.encode(v.value) end,
  BooleanValue = function(v) return cjson.encode(v.value) end,
  EnumValue = function(v) return v.value end,
  ListValue = function(v) return '[' .. table.concat(util.map(v.values, printAst), ', ') .. ']' end,
  ObjectValue = function(v) return '{' .. table.concat(util.map(v.fields, printAst), ', ') .. '}' end,
  ObjectField = function(v) return v.name .. ': ' .. v.value end
}

printAst = function(v)
  return printers[v.kind](v)
end

astFromValue = function(value, tt)

  -- Ensure flow knows that we treat function params as const.
  local _value = value

  if instanceof(tt,'NonNull') then
    -- Note: we're not checking that the result is non-null.
    -- This function is not responsible for validating the input value.
    return astFromValue(_value, tt.ofType)
  end

  if value == nil then
    return nil
  end

  -- Convert JavaScript array to GraphQL list. If the GraphQLType is a list, but
  -- the value is not an array, convert the value using the list's item type.
  if type(_value) == 'table' and #_value > 0 then
    local itemType = instanceof(tt, 'List') and tt.ofType or nil
    return {
      kind = Kind.LIST,
      values = util.map(_value, function(item)
        local itemValue = astFromValue(item, itemType)
        assert(itemValue, 'Could not create AST item.')
        return itemValue
      end)
    }
  elseif instanceof(tt, 'List') then
    -- Because GraphQL will accept single values as a "list of one" when
    -- expecting a list, if there's a non-array value and an expected list type,
    -- create an AST using the list's item type.
    return astFromValue(_value, tt.ofType)
  end

  if type(_value) == 'boolean' then
    return { kind = Kind.BOOLEAN, value = _value }
  end

  -- JavaScript numbers can be Float or Int values. Use the GraphQLType to
  -- differentiate if available, otherwise prefer Int if the value is a
  -- valid Int.
  if type(_value) == 'number' then
    local stringNum = String(_value)
    local isIntValue = _value%1 == 0
    if isIntValue then
      if tt == types.float then
        return { kind =  Kind.FLOAT, value = stringNum .. '.0' }
      end
      return { kind = Kind.INT, value = stringNum }
    end
    return { kind = Kind.FLOAT, value = stringNum }
  end

  -- JavaScript strings can be Enum values or String values. Use the
  -- GraphQLType to differentiate if possible.
  if type(_value) == 'string' then
    if instanceof(tt, 'Enum') and _value:match('/^[_a-zA-Z][_a-zA-Z0-9]*$/') then
      return { kind =Kind.ENUM, value = _value }
    end
    -- Use JSON stringify, which uses the same string encoding as GraphQL,
    -- then remove the quotes.
    return {
      kind = Kind.STRING,
      value = (cjson.encode(_value)):sub(1, -1)
    }
  end

  -- last remaining possible typeof
  assert(type(_value) == 'table')
  assert(_value ~= nil)

  -- Populate the fields of the input object by creating ASTs from each value
  -- in the JavaScript object.
  local fields = {}
  for fieldName,v in pairs(_value) do
    local fieldType
    if instanceof(tt, 'InputObject') then
      local fieldDef = tt.fields[fieldName]
      fieldType = fieldDef and fieldDef.kind
    end
    local fieldValue = astFromValue(_value[fieldName], fieldType)
    if fieldValue then
      table.insert(fields, {
        kind = Kind.OBJECT_FIELD,
        name = { kind = Kind.NAME, value = fieldName },
        value = fieldValue
      })
    end
  end

  return { kind = Kind.OBJECT, fields = fields }
end

return {
  __Schema = __Schema,
  __Directive = __Directive,
  __DirectiveLocation = __DirectiveLocation,
  __Type = __Type,
  __Field = __Field,
  __EnumValue = __EnumValue,
  __TypeKind = __TypeKind,
  SchemaMetaFieldDef = SchemaMetaFieldDef,
  TypeMetaFieldDef = TypeMetaFieldDef,
  TypeNameMetaFieldDef = TypeNameMetaFieldDef
}
