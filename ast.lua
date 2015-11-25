local lpeg = require 'lpeg'
local P, R, S, V, C, Ct, Cmt, Cg = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Ct, lpeg.Cmt, lpeg.Cg

-- Utility
local space = S(' \t\r\n') ^ 0
local comma = P(',') ^ -1

-- "Terminals"
local name = space * C(R('az', 'AZ') * (P('_') + R('09') + R('az', 'AZ')) ^ 0)
local alias = space * name * P(':')
local value = space * C(R('09') ^ 1) -- todo values are hard
local argument = space * Ct(Cg(name, 'name') * P(':') * Cg(value, 'value')) * comma
local arguments = P('(') * Ct(argument ^ 1) * P(')')
local fragmentName = space * (name - 'on')
local fragmentSpread = space * P('...') * fragmentName

-- Nonterminals
local graphQL = P {
  'input',
  input = space * V('selectionSet') * -1,
  selectionSet = space * P('{') * space * Ct(V('selection') ^ 0) * space * P('}'),
  selection = space * (V('field') + fragmentSpread),
  field = Ct(space * Cg(alias ^ -1, 'alias') * Cg(name, 'name') * Cg(arguments ^ -1, 'arguments') * Cg(V('selectionSet'), 'children') ^ 0) * comma,
}

return function(str)
  return graphQL:match(str)
end
