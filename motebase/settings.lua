local db = require("motebase.db")
local cjson = require("cjson")

local settings = {}

local DEFAULTS = {
    app_name = "MoteBase",
    app_url = "",
    sender_name = "MoteBase",
    sender_email = "",
    hide_controls = false,
}

function settings.init()
    local ok, err = db.exec([[
        CREATE TABLE IF NOT EXISTS _settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
    if not ok then return nil, err end

    for key, value in pairs(DEFAULTS) do
        local existing = db.query("SELECT key FROM _settings WHERE key = ?", { key })
        if not existing or #existing == 0 then
            local encoded_value
            if type(value) == "boolean" then
                encoded_value = value and "true" or "false"
            elseif type(value) == "table" then
                encoded_value = cjson.encode(value)
            else
                encoded_value = tostring(value)
            end
            db.insert("INSERT INTO _settings (key, value) VALUES (?, ?)", { key, encoded_value })
        end
    end

    return true
end

function settings.get(key)
    local rows = db.query("SELECT value FROM _settings WHERE key = ?", { key })
    if not rows or #rows == 0 then return DEFAULTS[key] end

    local value = rows[1].value
    local default = DEFAULTS[key]

    if type(default) == "boolean" then
        return value == "true"
    elseif type(default) == "number" then
        return tonumber(value)
    elseif type(default) == "table" then
        local ok, decoded = pcall(cjson.decode, value)
        if ok then return decoded end
        return default
    end

    return value
end

function settings.get_all()
    local rows = db.query("SELECT key, value, updated_at FROM _settings ORDER BY key")
    if not rows then return {} end

    local result = {}
    for _, row in ipairs(rows) do
        local default = DEFAULTS[row.key]
        local value = row.value

        if type(default) == "boolean" then
            value = value == "true"
        elseif type(default) == "number" then
            value = tonumber(value)
        elseif type(default) == "table" then
            local ok, decoded = pcall(cjson.decode, value)
            if ok then value = decoded end
        end

        result[row.key] = value
    end

    for key, value in pairs(DEFAULTS) do
        if result[key] == nil then result[key] = value end
    end

    return result
end

function settings.set(key, value)
    local encoded_value
    if type(value) == "boolean" then
        encoded_value = value and "true" or "false"
    elseif type(value) == "table" then
        encoded_value = cjson.encode(value)
    elseif value == nil then
        encoded_value = ""
    else
        encoded_value = tostring(value)
    end

    local existing = db.query("SELECT key FROM _settings WHERE key = ?", { key })
    if existing and #existing > 0 then
        local _, err = db.run(
            "UPDATE _settings SET value = ?, updated_at = strftime('%s', 'now') WHERE key = ?",
            { encoded_value, key }
        )
        if err then return nil, err end
    else
        local _, err = db.insert("INSERT INTO _settings (key, value) VALUES (?, ?)", { key, encoded_value })
        if err then return nil, err end
    end

    return true
end

function settings.update(updates)
    if type(updates) ~= "table" then return nil, "updates must be a table" end

    for key, value in pairs(updates) do
        local ok, err = settings.set(key, value)
        if not ok then return nil, err end
    end

    return settings.get_all()
end

function settings.get_storage_config()
    local backend = os.getenv("MOTEBASE_STORAGE_BACKEND") or "local"

    local config = {
        backend = backend,
        storage_path = os.getenv("MOTEBASE_STORAGE") or "./storage",
    }

    if backend == "s3" then
        config.s3 = {
            bucket = os.getenv("MOTEBASE_S3_BUCKET") or "",
            region = os.getenv("MOTEBASE_S3_REGION") or "",
            endpoint = os.getenv("MOTEBASE_S3_ENDPOINT") or "",

            access_key_set = os.getenv("MOTEBASE_S3_ACCESS_KEY") ~= nil,
            secret_key_set = os.getenv("MOTEBASE_S3_SECRET_KEY") ~= nil,
            path_style = os.getenv("MOTEBASE_S3_PATH_STYLE") == "true",
            use_ssl = os.getenv("MOTEBASE_S3_USE_SSL") ~= "false",
        }
    end

    return config
end

return settings
