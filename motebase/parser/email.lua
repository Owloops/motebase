-- RFC-5321 email validation (LGPL-3.0, Sean Conner)

local lpeg = require("lpeg")
local abnf = require("motebase.parser.abnf")

local Cs, P, R, S = lpeg.Cs, lpeg.P, lpeg.R, lpeg.S

local atext = abnf.ALPHA + abnf.DIGIT + S("!#$%&'*+-/=?^_`{|}~")
local dot_atom = atext ^ 1 * (P(".") * atext ^ 1) ^ 0
local qtext = R("  ", "!!", "#[", "]~")
local quoted_pair = P("\\") * (abnf.VCHAR + abnf.WSP)
local quoted_str = abnf.DQUOTE * Cs((qtext + quoted_pair) ^ 0) * abnf.DQUOTE
local local_part = dot_atom + quoted_str

local dtext = R("!Z", "^~")
local domain_lit = P("[") * (dtext + quoted_pair) ^ 0 * P("]")
local let_dig = abnf.ALPHA + abnf.DIGIT
local sub_domain = let_dig * (let_dig + P("-")) ^ 0
local domain = sub_domain * (P(".") * sub_domain) ^ 1 + domain_lit

local addr_spec = local_part * P("@") * domain * -1

local email = {}

function email.is_valid(addr)
    if not addr or type(addr) ~= "string" then return false end
    return lpeg.match(addr_spec, addr) ~= nil
end

function email.validate(addr)
    if not addr then return nil, "email required" end
    if type(addr) ~= "string" then return nil, "expected string" end
    if not lpeg.match(addr_spec, addr) then return nil, "invalid email format" end
    return addr
end

return email
