local path = (...):gsub('%.[^%.]+$', '')
local types = require(path .. '.types')
local util = require(path .. '.util')
local cjson = require 'cjson' -- needs to be cloned from here https://github.com/openresty/lua-cjson for cjson.empty_array feature
local function isNullish(value)
  return value == nil
end
local function instanceof(t, s)
  return t.__type == s
end
local function resolveDirective(directive)
  local res = {}
  if directive.onQuery then table.insert(res, 'QUERY') end
  if directive.onMutation then table.insert(res, 'MUTATION') end
  if directive.onSubscription then table.insert(res, 'SUBSCRIPTION') end
  if directive.onField then table.insert(res, 'FIELD') end
  if directive.onFragmentDefinition then table.insert(res, 'FRAGMENT_DEFINITION') end
  if directive.onFragmentSpread then table.insert(res, 'FRAGMENT_SPREAD') end
  if directive.onInlineFragment then table.insert(res, 'INLINE_FRAGMENT') end
  return res
end
local function mapToList(m)
  local r = {}
  for k,v in pairs(m) do
    table.insert(r, v)
  end
  return r
end
local __Schema, __Directive, __DirectiveLocation, __Type, __Field, __InputValue,__EnumValue, TypeKind, __TypeKind, SchemaMetaFieldDef, TypeMetaFieldDef, TypeNameMetaFieldDef, astFromValue, printAst, printers
local DirectiveLocation = {
  QUERY =  'QUERY', MUTATION =  'MUTATION', SUBSCRIPTION =  'SUBSCRIPTION', FIELD =  'FIELD', FRAGMENT_DEFINITION =  'FRAGMENT_DEFINITION', FRAGMENT_SPREAD =  'FRAGMENT_SPREAD', INLINE_FRAGMENT =  'INLINE_FRAGMENT'
}

__Schema = types.object({
  name = '__Schema',
  description =
    'A GraphQL Schema defines the capabilities of a GraphQL server. It ' ..
    'exposes all available types and directives on the server, as well as ' ..
    'the entry points for query, mutation, and subscription operations.',
  fields = function() return {
    types = {
      description = 'A list of all types supported by this server.',
      kind = types.nonNull(types.list(types.nonNull(__Type))),
      resolve = function(schema)
        local typeMap = schema:getTypeMap(); local res = {}
        for k,v in pairs(typeMap) do table.insert(res, typeMap[k]) end; return res
      end
    },
    queryType = {
      description = 'The type that query operations will be rooted at.',
      kind = types.nonNull(__Type),
      resolve = function(schema) return schema:getQueryType() end
    },
    mutationType = {
      description = 'If this server supports mutation, the type that ' ..
                   'mutation operations will be rooted at.',
      kind = __Type,
      resolve = function(schema) return schema:getMutationType() end
    },
    subscriptionType = {
      description = 'If this server support subscription, the type that ' ..
                   'subscription operations will be rooted at.',
      kind = __Type,
      resolve = function(schema) return schema:getSubscriptionType() end
    },
    directives = {
      description = 'A list of all directives supported by this server.',
      kind = 
        types.nonNull(types.list(types.nonNull(__Directive))),
      resolve = function(schema) return schema.directives end
    }
  } end
});

__Directive = types.object({
  name = '__Directive',
  description =
    'A Directive provides a way to describe alternate runtime execution and ' ..
    'type validation behavior in a GraphQL document.' ..
    '\n\nIn some cases, you need to provide options to alter GraphQL’s ' ..
    'execution behavior in ways field arguments will not suffice, such as ' ..
    'conditionally including or skipping a field. Directives provide this by ' ..
    'describing additional information to the executor.',
  fields = function() return {
    name = types.nonNull(types.string),
    description = types.string,
    locations = {
      kind = types.nonNull(types.list(types.nonNull(
        __DirectiveLocation
      ))), resolve = resolveDirective
    },
    args = {
      kind = 
        types.nonNull(types.list(types.nonNull(__InputValue))),
      --resolve = function(directive) return directive.arguments or {} end
      resolve = function(field)
        local args = {}
        local transform = function(a, n)
          if a.__type then
            return {kind = a, name = n}
          else
            if not a.name then
              local r = {name = n}
              for k,v in pairs(a) do
                r[k] = v
              end
              return r
            else
              return a
            end
          end
        end
        for k, v in pairs(field.arguments or {}) do table.insert(args, transform(v, k)) end
        -- p(args)
        -- return args
        if #args > 0 then return args else return cjson.empty_array end
      end
    },
    -- NOTE = the following three fields are deprecated and are no longer part
    -- of the GraphQL specification.
    onOperation = {
      deprecationReason = 'Use `locations`.',
      kind = types.nonNull(types.boolean),
      resolve = function(d) return
        d.locations:find(DirectiveLocation.QUERY) ~= nil or
        d.locations:find(DirectiveLocation.MUTATION) ~= nil or
        d.locations:find(DirectiveLocation.SUBSCRIPTION) ~= nil end
    },
    onFragment = {
      deprecationReason = 'Use `locations`.',
      kind = types.nonNull(types.boolean),
      resolve = function(d) return
        d.locations:find(DirectiveLocation.FRAGMENT_SPREAD) ~= nil or
        d.locations:find(DirectiveLocation.INLINE_FRAGMENT) ~= nil or
        d.locations:find(DirectiveLocation.FRAGMENT_DEFINITION) ~= nil end
    },
    onField = {
      deprecationReason = 'Use `locations`.',
      kind = types.nonNull(types.boolean),
      resolve = function(d) return d.locations:find(DirectiveLocation.FIELD) ~= nil end
    }
  } end
});

__DirectiveLocation = types.enum({
  name = '__DirectiveLocation',
  description =
    'A Directive can be adjacent to many parts of the GraphQL language, a ' ..
    '__DirectiveLocation describes one such possible adjacencies.',
  values = {
    QUERY = {
      value = DirectiveLocation.QUERY,
      description = 'Location adjacent to a query operation.'
    },
    MUTATION = {
      value = DirectiveLocation.MUTATION,
      description = 'Location adjacent to a mutation operation.'
    },
    SUBSCRIPTION = {
      value = DirectiveLocation.SUBSCRIPTION,
      description = 'Location adjacent to a subscription operation.'
    },
    FIELD = {
      value = DirectiveLocation.FIELD,
      description = 'Location adjacent to a field.'
    },
    FRAGMENT_DEFINITION = {
      value = DirectiveLocation.FRAGMENT_DEFINITION,
      description = 'Location adjacent to a fragment definition.'
    },
    FRAGMENT_SPREAD = {
      value = DirectiveLocation.FRAGMENT_SPREAD,
      description = 'Location adjacent to a fragment spread.'
    },
    INLINE_FRAGMENT = {
      value = DirectiveLocation.INLINE_FRAGMENT,
      description = 'Location adjacent to an inline fragment.'
    },
  }
});

__Type = types.object({
  name = '__Type',
  description =
    'The fundamental unit of any GraphQL Schema is the type. There are ' ..
    'many kinds of types in GraphQL as represented by the `__TypeKind` enum.' ..
    '\n\nDepending on the kind of a type, certain fields describe ' ..
    'information about that type. Scalar types provide no information ' ..
    'beyond a name and description, while Enum types provide their values. ' ..
    'Object and Interface types provide the fields they describe. Abstract ' ..
    'types, Union and Interface, provide the Object types possible ' ..
    'at runtime. List and NonNull types compose other types.',
  fields = function() return {
    kind = {
      kind = types.nonNull(__TypeKind),
      resolve = function (type)
        if instanceof(type, 'Scalar') then
          return TypeKind.SCALAR;
        elseif instanceof(type, 'Object') then
          return TypeKind.OBJECT;
        elseif instanceof(type, 'Interface') then
          return TypeKind.INTERFACE;
        elseif instanceof(type, 'Union') then
          return TypeKind.UNION;
        elseif instanceof(type, 'Enum') then
          return TypeKind.ENUM;
        elseif instanceof(type, 'InputObject') then
          return TypeKind.INPUT_OBJECT;
        elseif instanceof(type, 'List') then
          return TypeKind.LIST;
        elseif instanceof(type, 'NonNull') then
          return TypeKind.NON_NULL;
        end
        error('Unknown kind of kind = ' .. type);
      end
    },
    name = types.string,
    description = types.string,
    fields = {
      kind = types.list(types.nonNull(__Field)),
      arguments = {
        -- includeDeprecated = types.boolean 
        includeDeprecated = { kind = types.boolean, defaultValue = false }
      },
      resolve = function(t, args)
        if instanceof(t, 'Object') or
            instanceof(t, 'Interface') then
          
          local fieldMap = t.fields;
          local fields = {}; for k,v in pairs(fieldMap) do table.insert(fields, fieldMap[k]) end
          if not args.includeDeprecated then
            fields = util.filter(fields, function(field) return not field.deprecationReason end);
          end
          if #fields > 0 then return fields else return cjson.empty_array end
        end
        return nil;
      end
    },
    interfaces = {
      kind = types.list(types.nonNull(__Type)),
      resolve = function(type)
        if instanceof(type, 'Object') then
          return type.interfaces and type.interfaces or cjson.empty_array;
        end
      end
    },
    possibleTypes = {
      kind = types.list(types.nonNull(__Type)),
      resolve = function(type, args, context, obj)
        if instanceof(type, 'Interface') or
            instanceof(type, 'Union') then
          return context.schema:getPossibleTypes(type);
        end
      end
    },
    enumValues = {
      kind = types.list(types.nonNull(__EnumValue)),
      arguments = {
        -- includeDeprecated = types.boolean
        includeDeprecated = { kind = types.boolean, defaultValue = false }
      },
      resolve = function(type, args)
        if instanceof(type, 'Enum') then
          local values = type.values;
          if not args.includeDeprecated then
            values = util.filter(values, function(value) return not value.deprecationReason end);
          end
          return mapToList(values);
        end
      end
    },
    inputFields = {
      kind = types.list(types.nonNull(__InputValue)),
      resolve = function(type)
        if instanceof(type, 'InputObject') then
          local fieldMap = type.fields;
          local fields = {}; for k,v in pairs(fieldMap) do table.insert(fields, fieldMap[k]) end; return fields
        end
      end
    },
    ofType = { kind = __Type }
  } end
});

__Field = types.object({
  name = '__Field',
  description =
    'Object and Interface types are described by a list of Fields, each of ' ..
    'which has a name, potentially a list of arguments, and a return type.',
  fields = function() return {
    name = types.nonNull(types.string),
    description = types.string,
    args = {
      -- kind = types.list(__InputValue),
      kind = types.nonNull(types.list(types.nonNull(__InputValue))),
      resolve = function(field)
        local args = {}
        local transform = function(a, n)
          if a.__type then
            return {kind = a, name = n}
          else
            if not a.name then
              local r = {name = n}
              for k,v in pairs(a) do
                r[k] = v
              end
              return r
            else
              return a
            end
          end
        end
        for k, v in pairs(field.arguments or {}) do table.insert(args, transform(v, k)) end
        -- return args
        if #args > 0 then return args else return cjson.empty_array end
      end
    },
    type = { kind = types.nonNull(__Type), resolve = function(field) return field.kind end },
    isDeprecated = {
      kind = types.nonNull(types.boolean),
      resolve = function(field) return not isNullish(field.deprecationReason) end
    },
    deprecationReason = types.string

  } end
});

__InputValue = types.object({
  name = '__InputValue',
  description =
    'Arguments provided to Fields or Directives and the input fields of an ' ..
    'InputObject are represented as Input Values which describe their type ' ..
    'and optionally a default value.',
  fields = function() return {
    name = types.nonNull(types.string),
    description = types.string,
    type = { kind = types.nonNull(__Type), resolve = function(field) return field.kind end },
    defaultValue = {
      kind = types.string,
      description =
        'A GraphQL-formatted string representing the default value for this ' ..
        'input value.',
      resolve = function(inputVal) if isNullish(inputVal.defaultValue)
        then return nil
        else return printAst(astFromValue(inputVal.defaultValue, inputVal)) end end
    }
  } end
});

__EnumValue = types.object({
  name = '__EnumValue',
  description =
    'One possible value for a given Enum. Enum values are unique values, not ' ..
    'a placeholder for a string or numeric value. However an Enum value is ' ..
    'returned in a JSON response as a string.',
  fields = function() return {
    name = types.nonNull(types.string),
    description = types.string,
    isDeprecated = {
      kind = types.nonNull(types.boolean),
      resolve = function(enumValue) return not isNullish(enumValue.deprecationReason) end
    },
    deprecationReason = 
      types.string

  } end
});

TypeKind = {
  SCALAR = 'SCALAR',
  OBJECT = 'OBJECT',
  INTERFACE = 'INTERFACE',
  UNION = 'UNION',
  ENUM = 'ENUM',
  INPUT_OBJECT = 'INPUT_OBJECT',
  LIST = 'LIST',
  NON_NULL = 'NON_NULL'
};

__TypeKind = types.enum({
  name = '__TypeKind',
  description = 'An enum describing what kind of type a given `__Type` is.',
  values = {
    SCALAR = {
      value = TypeKind.SCALAR,
      description = 'Indicates this type is a scalar.'
    },
    OBJECT = {
      value = TypeKind.OBJECT,
      description = 'Indicates this type is an object. ' ..
                   '`fields` and `interfaces` are valid fields.'
    },
    INTERFACE = {
      value = TypeKind.INTERFACE,
      description = 'Indicates this type is an interface. ' ..
                   '`fields` and `possibleTypes` are valid fields.'
    },
    UNION = {
      value = TypeKind.UNION,
      description = 'Indicates this type is a union. ' ..
                   '`possibleTypes` is a valid field.'
    },
    ENUM = {
      value = TypeKind.ENUM,
      description = 'Indicates this type is an enum. ' ..
                   '`enumValues` is a valid field.'
    },
    INPUT_OBJECT = {
      value = TypeKind.INPUT_OBJECT,
      description = 'Indicates this type is an input object. ' ..
                   '`inputFields` is a valid field.'
    },
    LIST = {
      value = TypeKind.LIST,
      description = 'Indicates this type is a list. ' ..
                   '`ofType` is a valid field.'
    },
    NON_NULL = {
      value = TypeKind.NON_NULL,
      description = 'Indicates this type is a non-null. ' ..
                   '`ofType` is a valid field.'
    }
  }
});

--
-- Note that these are GraphQLFieldDefinition and not GraphQLFieldConfig,
-- so the format for args is different.
--

SchemaMetaFieldDef = {
  name = '__schema',
  kind = types.nonNull(__Schema),
  description = 'Access the current type schema of this server.',
  arguments = {},
  resolve = function(source, args, context, obj) return context.schema  end
};

TypeMetaFieldDef = {
  name = '__type',
  kind = __Type,
  description = 'Request the type information of a single type.',
  arguments = {
    name = types.nonNull(types.string)
  }
  --,resolve = function(source, { name } = { name = string }, context, { schema })
  --  return schema.getType(name) end
};

TypeNameMetaFieldDef = {
  name = '__typename',
  kind = types.nonNull(types.string),
  description = 'The name of the current Object type at runtime.',
  arguments = {},
  resolve = function(source, args, context, obj) return obj.parentType.name end
};


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

  if isNullish(_value) then
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
      local fieldDef = tt.fields[fieldName];
      fieldType = fieldDef and fieldDef.kind;
    end
    local fieldValue = astFromValue(_value[fieldName], fieldType);
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
  TypeKind = TypeKind,
  __TypeKind = __TypeKind,
  SchemaMetaFieldDef = SchemaMetaFieldDef,
  TypeMetaFieldDef = TypeMetaFieldDef,
  TypeNameMetaFieldDef = TypeNameMetaFieldDef

}

