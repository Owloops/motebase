-- IP address parsing (LGPL-3.0, Sean Conner)

local lpeg = require("lpeg")

local C, Cmt, P, R = lpeg.C, lpeg.Cmt, lpeg.P, lpeg.R

local DIGIT = R("09")
local HEXDIG = R("09", "AF", "af")

local dec_octet = Cmt(DIGIT ^ 1, function(_, pos, cap)
    if tonumber(cap) < 256 then return pos end
end)

local IPv4 = dec_octet * "." * dec_octet * "." * dec_octet * "." * dec_octet

local h16 = HEXDIG ^ -4
local h16c = h16 * P(":") * #HEXDIG
local ls32 = IPv4 + h16c * h16

local function mh16(n)
    local accum = h16
    for _ = 1, n do
        accum = h16c * accum
    end
    return accum
end

local function mh16c(n)
    local accum = h16c
    for _ = 2, n do
        accum = accum * h16c
    end
    return accum
end

local IPv6 = mh16c(6) * ls32
    + P("::") * mh16c(5) * ls32
    + P("::") * mh16c(4) * ls32
    + h16 * P("::") * mh16c(4) * ls32
    + P("::") * mh16c(3) * ls32
    + h16 * P("::") * mh16c(3) * ls32
    + mh16(1) * P("::") * mh16c(3) * ls32
    + P("::") * mh16c(2) * ls32
    + h16 * P("::") * mh16c(2) * ls32
    + mh16(1) * P("::") * mh16c(2) * ls32
    + mh16(2) * P("::") * mh16c(2) * ls32
    + P("::") * h16c * ls32
    + h16 * P("::") * h16c * ls32
    + mh16(1) * P("::") * h16c * ls32
    + mh16(2) * P("::") * h16c * ls32
    + mh16(3) * P("::") * h16c * ls32
    + P("::") * ls32
    + h16 * P("::") * ls32
    + mh16(1) * P("::") * ls32
    + mh16(2) * P("::") * ls32
    + mh16(3) * P("::") * ls32
    + mh16(4) * P("::") * ls32
    + P("::") * h16
    + h16 * P("::") * h16
    + mh16(1) * P("::") * h16
    + mh16(2) * P("::") * h16
    + mh16(3) * P("::") * h16
    + mh16(4) * P("::") * h16
    + mh16(5) * P("::") * h16
    + P("::")
    + h16 * P("::")
    + mh16(1) * P("::")
    + mh16(2) * P("::")
    + mh16(3) * P("::")
    + mh16(4) * P("::")
    + mh16(5) * P("::")
    + mh16(6) * P("::")

return {
    IPv4 = C(IPv4),
    IPv6 = C(IPv6),
}
