local db = require("motebase.db")
local schema = require("motebase.schema")
local cjson = require("cjson")
local files = require("motebase.files")
local multipart = require("motebase.multipart")

local collections = {}

local function get_file_fields(collection_schema)
    local file_fields = {}
    for field_name, def in pairs(collection_schema) do
        if def.type == "file" then file_fields[field_name] = true end
    end
    return file_fields
end

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

function collections.create_record(name, data, multipart_parts)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local file_fields = get_file_fields(collection.schema)
    local form_data = {}

    if multipart_parts then
        for field_name, part in pairs(multipart_parts) do
            if not multipart.is_file(part) and not file_fields[field_name] then form_data[field_name] = part.data end
        end
    end

    for k, v in pairs(data or {}) do
        if not file_fields[k] then form_data[k] = v end
    end

    local validated, errors = schema.validate(form_data, collection.schema)
    if errors or not validated then return nil, errors end

    local insert_fields = {}
    local placeholders = {}
    local insert_values = {}

    for field_name, value in pairs(validated) do
        insert_fields[#insert_fields + 1] = field_name
        placeholders[#placeholders + 1] = "?"
        if type(value) == "table" then
            insert_values[#insert_values + 1] = cjson.encode(value)
        else
            insert_values[#insert_values + 1] = value
        end
    end

    local sql = "INSERT INTO "
        .. name
        .. " ("
        .. table.concat(insert_fields, ", ")
        .. ") VALUES ("
        .. table.concat(placeholders, ", ")
        .. ")"
    local id, err = db.insert(sql, insert_values)
    if not id then return nil, err end

    if multipart_parts then
        local file_updates = {}
        for field_name in pairs(file_fields) do
            local part = multipart_parts[field_name]
            if part and multipart.is_file(part) then
                local unique_filename = files.generate_filename(part.filename)
                local mime_type = files.detect_mime_type(part.filename)

                local file_info, save_err = files.save(name, id, unique_filename, part.data, mime_type)
                if not file_info then
                    db.run("DELETE FROM " .. name .. " WHERE id = ?", { id })
                    files.delete_record_files(name, id)
                    return nil, "file upload failed: " .. save_err
                end

                file_updates[field_name] = files.serialize(file_info)
            end
        end

        if next(file_updates) then
            local sets = {}
            local update_values = {}
            for field_name, value in pairs(file_updates) do
                sets[#sets + 1] = field_name .. " = ?"
                update_values[#update_values + 1] = value
            end
            update_values[#update_values + 1] = id

            local update_sql = "UPDATE " .. name .. " SET " .. table.concat(sets, ", ") .. " WHERE id = ?"
            db.run(update_sql, update_values)
        end
    end

    return collections.get_record(name, id)
end

function collections.update_record(name, id, data, multipart_parts)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local existing = collections.get_record(name, id)
    if not existing then return nil, "record not found" end

    local file_fields = get_file_fields(collection.schema)
    local form_data = {}

    if multipart_parts then
        for field_name, part in pairs(multipart_parts) do
            if not multipart.is_file(part) and not file_fields[field_name] then form_data[field_name] = part.data end
        end
    end

    for k, v in pairs(data or {}) do
        if not file_fields[k] then form_data[k] = v end
    end

    local validated, errors = schema.validate(form_data, collection.schema)
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

    if multipart_parts then
        for field_name in pairs(file_fields) do
            local part = multipart_parts[field_name]
            if part and multipart.is_file(part) then
                local old_file_data = existing[field_name]
                if old_file_data and old_file_data ~= "" then
                    local old_file = files.deserialize(old_file_data)
                    if old_file and old_file.filename then files.delete(name, id, old_file.filename) end
                end

                local unique_filename = files.generate_filename(part.filename)
                local mime_type = files.detect_mime_type(part.filename)

                local file_info, save_err = files.save(name, id, unique_filename, part.data, mime_type)
                if not file_info then return nil, "file upload failed: " .. save_err end

                sets[#sets + 1] = field_name .. " = ?"
                values[#values + 1] = files.serialize(file_info)
            end
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

    files.delete_record_files(name, id)

    return true
end

return collections
