-- HTTP/1.1 request parser (LGPL-3.0, Sean Conner)

local lpeg = require("lpeg")
local abnf = require("motebase.parser.abnf")
local ih = require("motebase.parser.ih")
local mime = require("motebase.parser.mime")
local url = require("motebase.parser.url")

local C, Cc, Cf, Cg, Ct = lpeg.C, lpeg.Cc, lpeg.Cf, lpeg.Cg, lpeg.Ct
local P, R, S = lpeg.P, lpeg.R, lpeg.S

local separators = S([[()<>@,;:\"/[]?={}]]) + abnf.SP + abnf.HTAB
local token = (abnf.VCHAR - separators) ^ 1

local method = P("OPTIONS")
    + P("GET")
    + P("HEAD")
    + P("POST")
    + P("PUT")
    + P("DELETE")
    + P("TRACE")
    + P("CONNECT")
    + P("PATCH")
    + token

local version = P("HTTP/1.1") * Cc("1.1") + P("HTTP/1.0") * Cc("1.0") + Cc("0.9")

local request_line =
    Ct(Cg(C(method), "method") * abnf.WSP ^ 1 * Cg(url, "location") * abnf.WSP ^ 1 * Cg(version, "version"))

local content_len = R("09") ^ 1 / tonumber
local generic_val = C((P(1) - abnf.CRLF) ^ 0)

local header = ih.Hc("Content-Length") * ih.COLON * content_len * abnf.CRLF
    + ih.Hc("Content-Type") * ih.COLON * mime.grammar * abnf.CRLF
    + ih.Hc("Connection") * ih.COLON * C(token) * abnf.CRLF
    + ih.Hc("Host") * ih.COLON * C((P(1) - abnf.CRLF) ^ 1) * abnf.CRLF
    + ih.Hc("User-Agent") * ih.COLON * generic_val * abnf.CRLF
    + ih.Hc("Accept") * ih.COLON * generic_val * abnf.CRLF
    + ih.Hc("Authorization") * ih.COLON * generic_val * abnf.CRLF
    + ih.Hc("Cookie") * ih.COLON * generic_val * abnf.CRLF
    + ih.Hc("Origin") * ih.COLON * generic_val * abnf.CRLF
    + ih.Hc("Referer") * ih.COLON * generic_val * abnf.CRLF
    + ih.generic

local headers = Cf(Ct("") * Cg(header) ^ 0, function(t, k, v)
    if k then t[k:lower()] = v end
    return t
end)

local http = {}

function http.parse_request_line(line)
    if not line then return nil end
    return lpeg.match(request_line, line)
end

function http.parse_headers(header_block)
    if not header_block then return {} end
    local input = header_block
    if not input:match("\n$") then input = input .. "\n" end
    return lpeg.match(headers, input) or {}
end

function http.parse_path(full_path)
    if not full_path then return nil end
    local result = lpeg.match(url, full_path)
    if result then return result.path or full_path, result.query end
    return full_path, nil
end

return http
