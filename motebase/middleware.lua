local cjson = require("cjson")
local jwt = require("motebase.jwt")
local log = require("motebase.utils.log")
local multipart = require("motebase.multipart")

local encode, decode = cjson.encode, cjson.decode

local middleware = {}

local cors_base = {
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Methods"] = "GET, POST, PATCH, DELETE, OPTIONS",
    ["Access-Control-Allow-Headers"] = "Content-Type, Authorization",
}

function middleware.cors_headers()
    local headers = {}
    for k, v in pairs(cors_base) do
        headers[k] = v
    end
    return headers
end

function middleware.is_preflight(method)
    return method == "OPTIONS"
end

function middleware.extract_auth(headers, secret, options)
    local auth_header = headers["authorization"]
    if not auth_header then return nil end

    local token = auth_header:match("^Bearer%s+(.+)$")
    if not token then return nil end

    local payload, err = jwt.decode(token, secret, options)
    if not payload then return nil, err end

    log.auth_success(payload.sub, "jwt")

    return payload
end

function middleware.encode_json(data)
    return encode(data)
end

function middleware.parse_body(body_raw, headers)
    if not body_raw or body_raw == "" then return {} end

    local content_type = headers and headers["content-type"] or ""

    if multipart.is_multipart(content_type) then
        local boundary = multipart.get_boundary(content_type)
        if not boundary then return nil, "missing boundary in multipart request" end
        local parts, err = multipart.parse(body_raw, boundary)
        if not parts then return nil, "failed to parse multipart: " .. (err or "unknown error") end
        return parts, nil, true
    end

    local ok, data = pcall(decode, body_raw)
    if not ok then return nil, "invalid JSON: " .. tostring(data) end

    return data
end

return middleware
