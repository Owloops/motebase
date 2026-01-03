-- Internet Headers (LGPL-3.0, Sean Conner)

local lpeg = require("lpeg")
local abnf = require("motebase.parser.abnf")

local C, Cf, Cg, Ct = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct
local P, R = lpeg.P, lpeg.R

local char = R("AZ", "az") / function(c)
    return P(c:lower()) + P(c:upper())
end + P(1) / function(c)
    return P(c)
end

local H = Cf(char ^ 1, function(a, b)
    return a * b
end)

local COLON = P(":") * abnf.LWSP

local generic = C(R("AZ", "az", "09", "--", "__") ^ 1)
    * COLON
    * C((R("!\255") + (abnf.WSP + abnf.CRLF * abnf.WSP) ^ 1 / " ") ^ 0)
    * abnf.CRLF

local function headers(pattern)
    return Cf(Ct("") * Cg(pattern) ^ 1 * abnf.CRLF, function(t, k, v)
        t[k] = v
        return t
    end)
end

return {
    Hc = function(s)
        return H:match(s) / s
    end,
    H = function(s)
        return H:match(s)
    end,
    COLON = COLON,
    generic = generic,
    headers = headers,
}
