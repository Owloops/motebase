-- RFC-5234 ABNF core rules
-- Patterns from Sean Conner's LPeg-Parsers (LGPL-3.0)

local lpeg = require("lpeg")

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

return abnf
