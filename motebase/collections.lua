local db = require("motebase.db")
local schema = require("motebase.schema")
local cjson = require("cjson")

local collections = {}

function collections.init()
    return db.exec([[
        CREATE TABLE IF NOT EXISTS _collections (
            name TEXT PRIMARY KEY,
            schema TEXT NOT NULL,
            created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
end

function collections.create(name, fields)
    if not name:match("^[a-z_][a-z0-9_]*$") then return nil, "invalid collection name" end

    if name:sub(1, 1) == "_" then return nil, "collection name cannot start with underscore" end

    local existing = db.query("SELECT name FROM _collections WHERE name = ?", { name })
    if existing and #existing > 0 then return nil, "collection already exists" end

    local columns = { "id INTEGER PRIMARY KEY AUTOINCREMENT" }
    for field_name, def in pairs(fields) do
        local sql_type = schema.field_to_sql_type(def.type or "string")
        local nullable = def.required and " NOT NULL" or ""
        columns[#columns + 1] = field_name .. " " .. sql_type .. nullable
    end
    columns[#columns + 1] = "created_at INTEGER DEFAULT (strftime('%s', 'now'))"
    columns[#columns + 1] = "updated_at INTEGER DEFAULT (strftime('%s', 'now'))"

    local create_sql = "CREATE TABLE " .. name .. " (" .. table.concat(columns, ", ") .. ")"
    local ok, err = db.exec(create_sql)
    if not ok then return nil, err end

    local _, insert_err =
        db.insert("INSERT INTO _collections (name, schema) VALUES (?, ?)", { name, cjson.encode(fields) })
    if insert_err then return nil, insert_err end

    return true
end

function collections.list()
    return db.query("SELECT name, schema, created_at FROM _collections ORDER BY name")
end

function collections.get(name)
    local rows = db.query("SELECT name, schema, created_at FROM _collections WHERE name = ?", { name })
    if not rows or #rows == 0 then return nil end
    local collection = rows[1]
    collection.schema = cjson.decode(collection.schema)
    return collection
end

function collections.delete(name)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local ok, err = db.exec("DROP TABLE " .. name)
    if not ok then return nil, err end

    db.run("DELETE FROM _collections WHERE name = ?", { name })
    return true
end

-- records --

function collections.list_records(name, limit, offset)
    limit = limit or 100
    offset = offset or 0
    local sql = "SELECT * FROM " .. name .. " ORDER BY id DESC LIMIT ? OFFSET ?"
    return db.query(sql, { limit, offset })
end

function collections.get_record(name, id)
    local rows = db.query("SELECT * FROM " .. name .. " WHERE id = ?", { id })
    if not rows or #rows == 0 then return nil end
    return rows[1]
end

function collections.create_record(name, data)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local validated, errors = schema.validate(data, collection.schema)
    if errors or not validated then return nil, errors end

    local fields = {}
    local placeholders = {}
    local values = {}

    for field_name, value in pairs(validated) do
        fields[#fields + 1] = field_name
        placeholders[#placeholders + 1] = "?"
        if type(value) == "table" then
            values[#values + 1] = cjson.encode(value)
        else
            values[#values + 1] = value
        end
    end

    if #fields == 0 then return nil, "no valid fields provided" end

    local sql = "INSERT INTO "
        .. name
        .. " ("
        .. table.concat(fields, ", ")
        .. ") VALUES ("
        .. table.concat(placeholders, ", ")
        .. ")"
    local id, err = db.insert(sql, values)
    if not id then return nil, err end

    return collections.get_record(name, id)
end

function collections.update_record(name, id, data)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local existing = collections.get_record(name, id)
    if not existing then return nil, "record not found" end

    local validated, errors = schema.validate(data, collection.schema)
    if errors or not validated then return nil, errors end

    local sets = {}
    local values = {}

    for field_name, value in pairs(validated) do
        sets[#sets + 1] = field_name .. " = ?"
        if type(value) == "table" then
            values[#values + 1] = cjson.encode(value)
        else
            values[#values + 1] = value
        end
    end

    if #sets == 0 then return existing end

    sets[#sets + 1] = "updated_at = strftime('%s', 'now')"
    values[#values + 1] = id

    local sql = "UPDATE " .. name .. " SET " .. table.concat(sets, ", ") .. " WHERE id = ?"
    local _, err = db.run(sql, values)
    if err then return nil, err end

    return collections.get_record(name, id)
end

function collections.delete_record(name, id)
    local existing = collections.get_record(name, id)
    if not existing then return nil, "record not found" end

    local changes, err = db.run("DELETE FROM " .. name .. " WHERE id = ?", { id })
    if err then return nil, err end
    if changes == 0 then return nil, "record not found" end

    return true
end

return collections
