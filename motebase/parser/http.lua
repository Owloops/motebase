local lpeg = require("lpeg")
local abnf = require("motebase.parser.abnf")

local http = {}

-- patterns --

local P, R, S = lpeg.P, lpeg.R, lpeg.S

-- captures --

local C, Cf, Cg, Ct = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct

-- request line grammar --

local function build_request_line_grammar()
    local SP = S(" \t")
    local method = C(R("AZ") ^ 1)
    local uri = C((P(1) - SP) ^ 1)
    local version = C(R("09") * P(".") * R("09"))

    return method * SP ^ 1 * uri * SP ^ 1 * P("HTTP/") * version
end

local request_line_grammar = build_request_line_grammar()

-- header grammar --

local function build_header_grammar()
    local line_end = abnf.CRLF

    local header_name = C((P(1) - P(":") - line_end) ^ 1)
    local header_value = C((P(1) - line_end) ^ 0)
    local header = Cg(header_name * P(":") * abnf.WSP ^ 0 * header_value)

    return Cf(Ct("") * (header * line_end) ^ 0, function(t, k, v)
        t[k:lower()] = v
        return t
    end)
end

local header_grammar = build_header_grammar()

-- path/query grammar --

local function build_path_grammar()
    local path = C((P(1) - P("?")) ^ 1)
    local query = P("?") * C(P(1) ^ 0)

    return path * query ^ -1
end

local path_grammar = build_path_grammar()

-- public functions --

function http.parse_request_line(line)
    if not line then return nil end
    return lpeg.match(request_line_grammar, line)
end

function http.parse_header(line)
    if not line then return nil end

    local line_end = abnf.CRLF

    local header_name = C((P(1) - P(":") - line_end) ^ 1)
    local header_value = C((P(1) - line_end) ^ 0)
    local single_header = header_name * P(":") * abnf.WSP ^ 0 * header_value

    return lpeg.match(single_header, line)
end

function http.parse_headers(header_block)
    if not header_block then return {} end
    local result = lpeg.match(header_grammar, header_block .. "\n")
    return result or {}
end

function http.parse_path(full_path)
    if not full_path then return nil end
    local path, query = lpeg.match(path_grammar, full_path)
    return path or full_path, query
end

return http
