local lpeg = require("lpeg")

local email = {}

-- patterns --

local P, R, S = lpeg.P, lpeg.R, lpeg.S

-- rfc 5321 email grammar --

local function build_email_grammar()
    local ALPHA = R("az", "AZ")
    local DIGIT = R("09")

    local atext = ALPHA + DIGIT + S("!#$%&'*+-/=?^_`{|}~.")
    local dot_atom_text = atext ^ 1

    local let_dig = ALPHA + DIGIT
    local let_dig_hyp = let_dig + P("-")
    local sub_domain = let_dig * let_dig_hyp ^ 0
    local domain = sub_domain * (P(".") * sub_domain) ^ 1

    local local_part = dot_atom_text
    local addr_spec = local_part * P("@") * domain * -1

    return addr_spec
end

local email_grammar = build_email_grammar()

-- public functions --

function email.is_valid(addr)
    if not addr or type(addr) ~= "string" then return false end
    return lpeg.match(email_grammar, addr) ~= nil
end

function email.validate(addr)
    if not addr then return nil, "email required" end
    if type(addr) ~= "string" then return nil, "expected string" end
    if not lpeg.match(email_grammar, addr) then return nil, "invalid email format" end
    return addr
end

return email
