-- RFC 5321 Email Validation

local lpeg = require("lpeg")

local core = require("motebase.parser.core")

local Cs, P, R, S = lpeg.Cs, lpeg.P, lpeg.R, lpeg.S

-- patterns --

local ALPHA = core.ALPHA
local DIGIT = core.DIGIT
local VCHAR = core.VCHAR
local WSP = core.WSP
local DQUOTE = core.DQUOTE

local atext = ALPHA + DIGIT + S("!#$%&'*+-/=?^_`{|}~")
local dot_atom = atext ^ 1 * (P(".") * atext ^ 1) ^ 0
local qtext = R("  ", "!!", "#[", "]~")
local quoted_pair = P("\\") * (VCHAR + WSP)
local quoted_str = DQUOTE * Cs((qtext + quoted_pair) ^ 0) * DQUOTE
local local_part = dot_atom + quoted_str

local dtext = R("!Z", "^~")
local domain_lit = P("[") * (dtext + quoted_pair) ^ 0 * P("]")
local let_dig = ALPHA + DIGIT
local sub_domain = let_dig * (let_dig + P("-")) ^ 0
local domain = sub_domain * (P(".") * sub_domain) ^ 1 + domain_lit

local addr_spec = local_part * P("@") * domain * -1

-- module --

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
