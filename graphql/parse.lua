local luagraphqlparser = require('luagraphqlparser')

local function parse(s)
  local ast, err = luagraphqlparser.parse(s)
  if err ~= nil then
    error(err)
  end
  return ast
end

return {
  parse = parse,
}
