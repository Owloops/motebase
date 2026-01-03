-- RFC-3986 URL parser (LGPL-3.0, Sean Conner)

local lpeg = require("lpeg")
local abnf = require("motebase.parser.abnf")
local ip = require("motebase.parser.ip")

local C, Cc, Cg, Cs, Ct = lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cs, lpeg.Ct
local P, S = lpeg.P, lpeg.S

local pct_encoded = (P("%") * abnf.HEXDIG * abnf.HEXDIG)
    / function(capture)
        return string.char(tonumber(capture:sub(2, -1), 16))
    end

local sub_delims = S("!$&'()*+,;=")
local unreserved = abnf.ALPHA + abnf.DIGIT + S("-._~")
local pchar = unreserved + pct_encoded + sub_delims + S(":@")

local segment = pchar ^ 0
local segment_nz = pchar ^ 1
local segment_nz_nc = (unreserved + pct_encoded + sub_delims + P("@")) ^ 1

local path_abempty = Cs((P("/") * segment) ^ 1) + Cc("/")
local path_absolute = Cs(P("/") * (segment_nz * (P("/") * segment) ^ 0) ^ -1)
local path_noscheme = Cs(segment_nz_nc * (P("/") * segment) ^ 0)
local path_rootless = Cs(segment_nz * (P("/") * segment) ^ 0)
local path_empty = Cc("/")

local reg_name = Cs((unreserved + pct_encoded + sub_delims) ^ 0)
local host = Cg(P("[") * (ip.IPv6 + ip.IPv4) * P("]") + ip.IPv4 + reg_name, "host")
local port = Cg(abnf.DIGIT ^ 1 / tonumber, "port")
local userinfo = Cg(Cs((unreserved + pct_encoded + sub_delims + P(":")) ^ 0), "user")
local authority = (userinfo * P("@")) ^ -1 * host * (P(":") * port) ^ -1

local query = Cg(C((pchar + S("/?")) ^ 0), "query")
local fragment = Cg(Cs((pchar + S("/?")) ^ 0), "fragment")

local scheme_https = P("https") * #P(":") * Cg(Cc("https"), "scheme") * Cg(Cc(443), "port")
local scheme_http = P("http") * #P(":") * Cg(Cc("http"), "scheme") * Cg(Cc(80), "port")
local scheme_ftp = P("ftp") * #P(":") * Cg(Cc("ftp"), "scheme") * Cg(Cc(21), "port")
local scheme_file = P("file") * #P(":") * Cg(Cc("file"), "scheme")
local scheme_generic = Cg(C(abnf.ALPHA * (abnf.ALPHA + abnf.DIGIT + S("+-.")) ^ 0), "scheme")
local scheme = scheme_https + scheme_http + scheme_ftp + scheme_file + scheme_generic

local hier_part = P("//") * authority * Cg(path_abempty, "path")
    + Cg(path_absolute, "path")
    + Cg(path_rootless, "path")
    + Cg(path_empty, "path")

local relative_part = P("//") * authority * Cg(path_abempty, "path")
    + Cg(path_absolute, "path")
    + Cg(path_noscheme, "path")
    + Cg(path_empty, "path")

local relative_ref = relative_part * (P("?") * query) ^ -1 * (P("#") * fragment) ^ -1

local URI = scheme * P(":") * hier_part * (P("?") * query) ^ -1 * (P("#") * fragment) ^ -1

return Ct(URI + relative_ref)
