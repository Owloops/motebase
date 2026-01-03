local storage = require("motebase.storage")
local crypto = require("motebase.crypto")
local cjson = require("cjson")

local files = {}

-- config --

local config = {
    max_file_size = 10 * 1024 * 1024,
    allowed_types = nil,
    storage_path = "./storage",
    file_token_duration = 120,
    secret = nil,
}

function files.configure(opts)
    if opts.max_file_size then config.max_file_size = opts.max_file_size end
    if opts.allowed_types then config.allowed_types = opts.allowed_types end
    if opts.storage_path then config.storage_path = opts.storage_path end
    if opts.file_token_duration then config.file_token_duration = opts.file_token_duration end
    if opts.secret ~= nil then config.secret = opts.secret end
end

function files.init()
    return storage.init({ storage_path = config.storage_path })
end

-- mime types --

local mime_types = {
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    png = "image/png",
    gif = "image/gif",
    webp = "image/webp",
    svg = "image/svg+xml",
    ico = "image/x-icon",
    bmp = "image/bmp",
    pdf = "application/pdf",
    doc = "application/msword",
    docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xls = "application/vnd.ms-excel",
    xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    txt = "text/plain",
    csv = "text/csv",
    zip = "application/zip",
    gz = "application/gzip",
    tar = "application/x-tar",
    mp3 = "audio/mpeg",
    wav = "audio/wav",
    ogg = "audio/ogg",
    mp4 = "video/mp4",
    webm = "video/webm",
    html = "text/html",
    css = "text/css",
    js = "application/javascript",
    json = "application/json",
    xml = "application/xml",
}

function files.detect_mime_type(filename)
    local ext = filename:match("%.([^%.]+)$")
    if ext then return mime_types[ext:lower()] or "application/octet-stream" end
    return "application/octet-stream"
end

-- filename handling --

function files.sanitize_filename(filename)
    filename = filename:match("[^/\\]+$") or filename
    filename = filename:gsub("[^%w%.%-_]", "_")
    filename = filename:gsub("^%.", "_")

    if #filename > 200 then
        local ext = filename:match("%.([^%.]+)$") or ""
        local base = filename:sub(1, 200 - #ext - 1)
        filename = base .. "." .. ext
    end

    return filename
end

function files.generate_filename(original_name)
    local sanitized = files.sanitize_filename(original_name)
    local suffix = crypto.to_hex(crypto.random_bytes(8))
    local ext = sanitized:match("%.([^%.]+)$")
    local base = sanitized:gsub("%.[^%.]+$", "")

    if ext then return base .. "_" .. suffix .. "." .. ext end
    return sanitized .. "_" .. suffix
end

-- paths --

function files.get_path(collection_name, record_id, filename)
    return string.format("%s/%d/%s", collection_name, record_id, filename)
end

-- operations --

function files.save(collection_name, record_id, filename, data, mime_type)
    if #data > config.max_file_size then
        return nil, "file too large (max " .. (config.max_file_size / 1024 / 1024) .. "MB)"
    end

    if config.allowed_types then
        local allowed = false
        for i = 1, #config.allowed_types do
            local t = config.allowed_types[i]
            if mime_type == t or mime_type:match("^" .. t:gsub("*", ".*") .. "$") then
                allowed = true
                break
            end
        end
        if not allowed then return nil, "file type not allowed: " .. mime_type end
    end

    local path = files.get_path(collection_name, record_id, filename)
    local ok, err = storage.write(path, data)
    if not ok then return nil, err end

    return {
        filename = filename,
        size = #data,
        mime_type = mime_type,
    }
end

function files.read(collection_name, record_id, filename)
    local path = files.get_path(collection_name, record_id, filename)
    return storage.read(path)
end

function files.delete(collection_name, record_id, filename)
    local path = files.get_path(collection_name, record_id, filename)
    return storage.delete(path)
end

function files.delete_record_files(collection_name, record_id)
    local path = string.format("%s/%d", collection_name, record_id)
    return storage.delete_dir(path)
end

-- serialization --

function files.serialize(file_info)
    if type(file_info) == "table" then return cjson.encode(file_info) end
    return file_info
end

function files.deserialize(data)
    if type(data) == "string" and data ~= "" then
        local ok, result = pcall(cjson.decode, data)
        if ok then return result end
    end
    return data
end

function files.get_max_size()
    return config.max_file_size
end

-- file tokens --

function files.create_token()
    if not config.secret then return nil, "secret not configured" end

    local payload = {
        purpose = "file",
        iat = os.time(),
        exp = os.time() + config.file_token_duration,
        jti = crypto.to_hex(crypto.random_bytes(8)),
    }

    local payload_json = cjson.encode(payload)
    local payload_b64 = crypto.base64url_encode(payload_json)
    local signature = crypto.hmac_sha256(config.secret, payload_b64)
    local signature_b64 = crypto.base64url_encode(signature)

    return payload_b64 .. "." .. signature_b64, config.file_token_duration
end

function files.verify_token(token)
    if not token or not config.secret then return nil, "invalid token" end

    local parts = {}
    for part in token:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    if #parts ~= 2 then return nil, "invalid token format" end

    local payload_b64, signature_b64 = parts[1], parts[2]
    local expected_sig = crypto.base64url_encode(crypto.hmac_sha256(config.secret, payload_b64))

    if not crypto.constant_time_compare(signature_b64, expected_sig) then return nil, "invalid signature" end

    local ok, payload = pcall(cjson.decode, crypto.base64url_decode(payload_b64))
    if not ok then return nil, "invalid payload" end

    if payload.purpose ~= "file" then return nil, "invalid token purpose" end

    if payload.exp and os.time() > payload.exp then return nil, "token expired" end

    return payload
end

return files
