-- RFC-5234 ABNF / RFC-2045 MIME primitives
-- Patterns from Sean Conner's LPeg-Parsers (LGPL-3.0)

local lpeg = require("lpeg")

-- rfc 5234 abnf --

local abnf = {
    ALPHA = lpeg.R("AZ", "az"),
    BIT = lpeg.P("0") + lpeg.P("1"),
    CHAR = lpeg.R("\1\127"),
    CR = lpeg.P("\r"),
    CRLF = lpeg.P("\r") ^ -1 * lpeg.P("\n"),
    CTL = lpeg.R("\0\31", "\127\127"),
    DIGIT = lpeg.R("09"),
    DQUOTE = lpeg.P('"'),
    HEXDIG = lpeg.R("09", "AF", "af"),
    HTAB = lpeg.P("\t"),
    LF = lpeg.P("\n"),
    OCTET = lpeg.P(1),
    SP = lpeg.P(" "),
    VCHAR = lpeg.R("!~"),
}

abnf.WSP = abnf.SP + abnf.HTAB
abnf.LWSP = (abnf.WSP + abnf.CRLF * abnf.WSP) ^ 0

-- rfc 2045 mime --

local tspecials = lpeg.S([[()<>@,;:\"/[]?=]])
abnf.token = (lpeg.P(1) - tspecials - abnf.CTL - abnf.WSP) ^ 1

local qtext = lpeg.P(1) - lpeg.S('"\\') - abnf.CRLF
local quoted_pair = lpeg.P("\\") * lpeg.C(lpeg.P(1))
abnf.quoted_string = abnf.DQUOTE * lpeg.Cs((qtext + quoted_pair) ^ 0) * abnf.DQUOTE

abnf.param_value = abnf.quoted_string + lpeg.C(abnf.token)

return abnf
