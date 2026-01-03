local lpeg = require("lpeg")

local primitives = {}

-- patterns --

local P, R, S = lpeg.P, lpeg.R, lpeg.S

-- captures --

local C, Cs = lpeg.C, lpeg.Cs

-- rfc 2045/2046 primitives --

primitives.CRLF = P("\r\n")
primitives.LF = P("\n")
primitives.LWSP = S(" \t")
primitives.DIGIT = R("09")
primitives.ALPHA = R("az", "AZ")

local tspecials = S([[()<>@,;:\"/[]?=]])
local CTL = R("\0\31") + P("\127")
primitives.token = (P(1) - tspecials - CTL - S(" \t")) ^ 1

local qtext = P(1) - S('"\\') - primitives.CRLF - primitives.LF
local quoted_pair = P("\\") * C(P(1))
primitives.quoted_string = P('"') * Cs((qtext + quoted_pair) ^ 0) * P('"')

primitives.param_value = primitives.quoted_string + C(primitives.token)

return primitives
