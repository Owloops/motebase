-- S3 Client with AWS Signature V4

local https = require("ssl.https")
local http = require("socket.http")
local ltn12 = require("ltn12")
local crypto = require("motebase.crypto")

local format, byte = string.format, string.byte
local insert, concat, sort = table.insert, table.concat, table.sort
local date = os.date
local pairs = pairs

local s3 = {}

-- config --

local config = {
    bucket = nil,
    region = "us-east-1",
    endpoint = nil,
    access_key = nil,
    secret_key = nil,
    path_style = false,
    use_ssl = true,
}

function s3.configure(opts)
    config.bucket = opts.bucket
    config.region = opts.region or "us-east-1"
    config.endpoint = opts.endpoint
    config.access_key = opts.access_key
    config.secret_key = opts.secret_key
    config.path_style = opts.path_style or false
    config.use_ssl = opts.use_ssl ~= false

    if not config.endpoint and config.bucket then config.endpoint = "s3." .. config.region .. ".amazonaws.com" end
end

function s3.reset()
    config.bucket = nil
    config.region = "us-east-1"
    config.endpoint = nil
    config.access_key = nil
    config.secret_key = nil
    config.path_style = false
    config.use_ssl = true
end

-- helpers --

local function sha256_hex(data)
    return crypto.to_hex(crypto.sha256(data or ""))
end

local function uri_encode(str, encode_slash)
    if not str then return "" end
    local result = {}
    for i = 1, #str do
        local c = str:sub(i, i)
        if c:match("[A-Za-z0-9_.~-]") then
            insert(result, c)
        elseif c == "/" and not encode_slash then
            insert(result, c)
        else
            insert(result, format("%%%02X", byte(c)))
        end
    end
    return concat(result)
end

local function get_amz_date()
    return date("!%Y%m%dT%H%M%SZ")
end

local function get_datestamp()
    return date("!%Y%m%d")
end

-- signing --

local function get_host_and_uri(key)
    local host, uri
    if config.path_style then
        host = config.endpoint
        uri = "/" .. config.bucket .. "/" .. uri_encode(key, false)
    else
        host = config.bucket .. "." .. config.endpoint
        uri = "/" .. uri_encode(key, false)
    end
    return host, uri
end

local function create_canonical_request(method, uri, query, headers, signed_headers, payload_hash)
    local canonical_headers = {}
    for i = 1, #signed_headers do
        local name = signed_headers[i]
        insert(canonical_headers, name .. ":" .. headers[name])
    end

    return concat({
        method,
        uri,
        query or "",
        concat(canonical_headers, "\n") .. "\n",
        concat(signed_headers, ";"),
        payload_hash,
    }, "\n")
end

local function create_string_to_sign(canonical_request, amz_date, datestamp)
    local scope = datestamp .. "/" .. config.region .. "/s3/aws4_request"
    local request_hash = sha256_hex(canonical_request)

    return concat({
        "AWS4-HMAC-SHA256",
        amz_date,
        scope,
        request_hash,
    }, "\n"),
        scope
end

local function calculate_signature(string_to_sign, datestamp)
    local k_date = crypto.hmac_sha256("AWS4" .. config.secret_key, datestamp)
    local k_region = crypto.hmac_sha256(k_date, config.region)
    local k_service = crypto.hmac_sha256(k_region, "s3")
    local k_signing = crypto.hmac_sha256(k_service, "aws4_request")
    return crypto.to_hex(crypto.hmac_sha256(k_signing, string_to_sign))
end

local function sign_request(method, key, extra_headers, body, query)
    local amz_date = get_amz_date()
    local datestamp = get_datestamp()
    local payload_hash = sha256_hex(body)
    local host, uri = get_host_and_uri(key)

    local headers = {
        ["host"] = host,
        ["x-amz-date"] = amz_date,
        ["x-amz-content-sha256"] = payload_hash,
    }

    if extra_headers then
        for k, v in pairs(extra_headers) do
            headers[k:lower()] = v
        end
    end

    local signed_headers = {}
    for k in pairs(headers) do
        insert(signed_headers, k)
    end
    sort(signed_headers)

    local canonical_request = create_canonical_request(method, uri, query, headers, signed_headers, payload_hash)

    local string_to_sign, scope = create_string_to_sign(canonical_request, amz_date, datestamp)

    local signature = calculate_signature(string_to_sign, datestamp)

    headers["authorization"] = format(
        "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
        config.access_key,
        scope,
        concat(signed_headers, ";"),
        signature
    )

    local request_headers = {}
    for k, v in pairs(headers) do
        request_headers[k] = v
    end

    return host, uri, request_headers
end

-- operations --

local function make_request(method, key, body, extra_headers, query)
    local host, uri, headers = sign_request(method, key, extra_headers, body, query)

    local protocol = config.use_ssl and "https" or "http"
    local url = protocol .. "://" .. host .. uri
    if query and query ~= "" then url = url .. "?" .. query end

    local response = {}
    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(response),
    }

    if body and #body > 0 then request.source = ltn12.source.string(body) end

    local client = config.use_ssl and https or http
    local _, code, response_headers = client.request(request)

    return code, concat(response), response_headers
end

function s3.put(key, data, content_type)
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local headers = {
        ["content-length"] = tostring(#data),
    }
    if content_type then headers["content-type"] = content_type end

    local code, body = make_request("PUT", key, data, headers)

    if code ~= 200 and code ~= 204 then return nil, "S3 PUT failed: " .. tostring(code) .. " " .. tostring(body) end

    return true
end

function s3.get(key)
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local code, body = make_request("GET", key, nil, nil)

    if code == 404 then return nil, "not found" end

    if code ~= 200 then return nil, "S3 GET failed: " .. tostring(code) .. " " .. tostring(body) end

    return body
end

function s3.delete(key)
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local code, body = make_request("DELETE", key, nil, nil)

    if code ~= 200 and code ~= 204 then return nil, "S3 DELETE failed: " .. tostring(code) .. " " .. tostring(body) end

    return true
end

function s3.head(key)
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local code = make_request("HEAD", key, nil, nil)

    if code == 404 then return false end

    if code ~= 200 then return nil, "S3 HEAD failed: " .. tostring(code) end

    return true
end

function s3.list(prefix)
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local query = "list-type=2"
    if prefix and prefix ~= "" then query = query .. "&prefix=" .. uri_encode(prefix, true) end

    local code, body = make_request("GET", "", nil, nil, query)

    if code ~= 200 then return nil, "S3 LIST failed: " .. tostring(code) .. " " .. tostring(body) end

    local keys = {}
    for key in body:gmatch("<Key>([^<]+)</Key>") do
        insert(keys, key)
    end

    return keys
end

function s3.test_connection()
    if not config.bucket then return nil, "bucket not configured" end
    if not config.access_key then return nil, "access_key not configured" end
    if not config.secret_key then return nil, "secret_key not configured" end

    local keys, err = s3.list("")
    if not keys then return nil, "connection test failed: " .. tostring(err) end

    return true
end

return s3
