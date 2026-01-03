local lpeg = require("lpeg")
local prim = require("motebase.parser.primitives")

local multipart = {}

-- patterns --

local P = lpeg.P

-- captures --

local C, Cf, Cg, Ct = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct

-- disposition grammar --

local function build_disposition_grammar()
    local LWSP = prim.LWSP
    local token = prim.token
    local param_value = prim.param_value

    local param = Cg(C(token) * P("=") * param_value)
    local params = Cf(Ct("") * (P(";") * LWSP ^ 0 * param) ^ 0, rawset)

    return P("form-data") * params
end

local disposition_grammar = build_disposition_grammar()

-- header grammar --

local function build_header_grammar()
    local CRLF = prim.CRLF
    local LF = prim.LF
    local LWSP = prim.LWSP
    local token = prim.token
    local line_end = CRLF + LF

    local header_name = C(token)
    local header_value = C((P(1) - line_end) ^ 0)
    local header = Cg(header_name * P(":") * LWSP ^ 0 * header_value)
    local headers = Cf(Ct("") * (header * line_end) ^ 0, rawset)

    return headers
end

local header_grammar = build_header_grammar()

-- boundary extraction --

function multipart.get_boundary(content_type)
    if not content_type then return nil end

    local boundary_pattern = P("boundary=") * prim.param_value
    local skip = (P(1) - P("boundary=")) ^ 0
    local grammar = skip * boundary_pattern

    return lpeg.match(grammar, content_type)
end

-- multipart check --

function multipart.is_multipart(content_type)
    if not content_type then return false end
    return content_type:sub(1, 19) == "multipart/form-data"
end

-- part parsing --

local function parse_part(part_content)
    local sep = "\r\n\r\n"
    local header_end = part_content:find(sep, 1, true)
    local body_start = 4

    if not header_end then
        sep = "\n\n"
        header_end = part_content:find(sep, 1, true)
        body_start = 2
    end

    if not header_end then return nil, "malformed part: no header/body separator" end

    local header_section = part_content:sub(1, header_end - 1)
    local body = part_content:sub(header_end + body_start)

    local headers = lpeg.match(header_grammar, header_section .. "\n")
    if not headers then return nil, "failed to parse headers" end

    local disposition_header = nil
    for k, v in pairs(headers) do
        if k:lower() == "content-disposition" then
            disposition_header = v
            break
        end
    end

    if not disposition_header then return nil, "missing Content-Disposition header" end

    local params = lpeg.match(disposition_grammar, disposition_header)
    if not params then return nil, "failed to parse Content-Disposition" end

    local content_type = nil
    for k, v in pairs(headers) do
        if k:lower() == "content-type" then
            content_type = v
            break
        end
    end

    return {
        name = params.name,
        filename = params.filename,
        content_type = content_type or "text/plain",
        data = body,
    }
end

-- main parse function --

function multipart.parse(body, boundary)
    if not body or not boundary then return nil, "missing body or boundary" end

    local parts = {}
    local delimiter = "--" .. boundary

    local pos = body:find(delimiter, 1, true)
    if not pos then return nil, "no parts found" end

    while true do
        pos = pos + #delimiter

        local next_two = body:sub(pos, pos + 1)
        if next_two == "\r\n" then
            pos = pos + 2
        elseif body:sub(pos, pos) == "\n" then
            pos = pos + 1
        elseif next_two == "--" then
            break
        end

        local next_delim = body:find(delimiter, pos, true)
        if not next_delim then break end

        local part_content = body:sub(pos, next_delim - 1)
        part_content = part_content:gsub("\r?\n$", "")

        local part = parse_part(part_content)
        if part and part.name then parts[part.name] = part end

        local after_delim = body:sub(next_delim + #delimiter, next_delim + #delimiter + 1)
        if after_delim == "--" then break end

        pos = next_delim
    end

    return parts
end

-- file detection --

function multipart.is_file(part)
    return part and part.filename and part.filename ~= ""
end

return multipart
