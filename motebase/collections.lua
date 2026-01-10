local db = require("motebase.db")
local schema = require("motebase.schema")
local cjson = require("cjson")
local crypto = require("motebase.crypto")
local files = require("motebase.files")
local multipart = require("motebase.parser.multipart")
local query = require("motebase.query")
local expand = require("motebase.query.expand")
local realtime = require("motebase.realtime")

local collections = {}

local schema_cache = {}

local RULE_FIELDS = { "listRule", "viewRule", "createRule", "updateRule", "deleteRule" }

local ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
local ID_LENGTH = 15

local function generate_id()
    local bytes = crypto.random_bytes(ID_LENGTH)
    local id = {}
    for i = 1, ID_LENGTH do
        local idx = (string.byte(bytes, i) % 36) + 1
        id[i] = ID_CHARS:sub(idx, idx)
    end
    return table.concat(id)
end

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
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            schema TEXT NOT NULL,
            type TEXT DEFAULT 'base',
            listRule TEXT,
            viewRule TEXT,
            createRule TEXT,
            updateRule TEXT,
            deleteRule TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
end

function collections.create(name, fields, rules, collection_type)
    if not name:match("^[a-z_][a-z0-9_]*$") then return nil, "invalid collection name" end

    if name:sub(1, 1) == "_" then return nil, "collection name cannot start with underscore" end

    local existing = db.query("SELECT name FROM _collections WHERE name = ?", { name })
    if existing and #existing > 0 then return nil, "collection already exists" end

    collection_type = collection_type or "base"
    if collection_type ~= "base" and collection_type ~= "auth" then
        return nil, "invalid collection type (must be 'base' or 'auth')"
    end

    -- Auth collections require email field
    if collection_type == "auth" then fields.email = fields.email or { type = "email", required = true } end

    local columns = { "id INTEGER PRIMARY KEY AUTOINCREMENT" }
    for field_name, def in pairs(fields) do
        local sql_type = schema.field_to_sql_type(def.type or "string")
        local nullable = def.required and " NOT NULL" or ""
        columns[#columns + 1] = field_name .. " " .. sql_type .. nullable
    end

    if collection_type == "auth" then columns[#columns + 1] = "password_hash TEXT" end

    columns[#columns + 1] = "created_at INTEGER DEFAULT (strftime('%s', 'now'))"
    columns[#columns + 1] = "updated_at INTEGER DEFAULT (strftime('%s', 'now'))"

    local create_sql = "CREATE TABLE " .. name .. " (" .. table.concat(columns, ", ") .. ")"
    local ok, err = db.exec(create_sql)
    if not ok then return nil, err end

    local collection_id = generate_id()
    rules = rules or {}
    local _, insert_err = db.insert(
        "INSERT INTO _collections (id, name, schema, type, listRule, viewRule, createRule, updateRule, deleteRule) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
            collection_id,
            name,
            cjson.encode(fields),
            collection_type,
            rules.listRule,
            rules.viewRule,
            rules.createRule,
            rules.updateRule,
            rules.deleteRule,
        }
    )
    if insert_err then return nil, insert_err end

    schema_cache[name] = nil
    return collection_id
end

function collections.list()
    local rows = db.query(
        "SELECT id, name, schema, type, listRule, viewRule, createRule, updateRule, deleteRule, created_at FROM _collections ORDER BY name"
    )
    if not rows then return nil end
    for i = 1, #rows do
        rows[i].schema = cjson.decode(rows[i].schema)
    end
    return rows
end

function collections.get(name)
    if schema_cache[name] then return schema_cache[name] end

    local rows = db.query(
        "SELECT id, name, schema, type, listRule, viewRule, createRule, updateRule, deleteRule, created_at FROM _collections WHERE name = ?",
        { name }
    )
    if not rows or #rows == 0 then return nil end
    local collection = rows[1]
    collection.schema = cjson.decode(collection.schema)
    schema_cache[name] = collection
    return collection
end

function collections.get_by_id(id)
    local rows = db.query(
        "SELECT id, name, schema, type, listRule, viewRule, createRule, updateRule, deleteRule, created_at FROM _collections WHERE id = ?",
        { id }
    )
    if not rows or #rows == 0 then return nil end
    local collection = rows[1]
    collection.schema = cjson.decode(collection.schema)
    return collection
end

function collections.update(name, updates)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local sets = {}
    local values = {}

    for i = 1, #RULE_FIELDS do
        local field = RULE_FIELDS[i]
        if updates[field] ~= nil then
            sets[#sets + 1] = field .. " = ?"
            if updates[field] == cjson.null then
                values[#values + 1] = nil
            else
                values[#values + 1] = updates[field]
            end
        end
    end

    if updates.schema then
        local current_schema = collection.schema or {}
        local new_schema = updates.schema

        for field_name, def in pairs(new_schema) do
            if not current_schema[field_name] then
                local sql_type = schema.field_to_sql_type(def.type or "string")
                local alter_sql = "ALTER TABLE " .. name .. " ADD COLUMN " .. field_name .. " " .. sql_type
                local ok, err = db.exec(alter_sql)
                if not ok then return nil, "failed to add column " .. field_name .. ": " .. (err or "unknown error") end
            end
        end

        sets[#sets + 1] = "schema = ?"
        values[#values + 1] = cjson.encode(new_schema)
    end

    if #sets == 0 then return collection end

    values[#values + 1] = name
    local sql = "UPDATE _collections SET " .. table.concat(sets, ", ") .. " WHERE name = ?"
    local _, err = db.run(sql, values)
    if err then return nil, err end

    schema_cache[name] = nil
    return collections.get(name)
end

function collections.delete(name)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local ok, err = db.exec("DROP TABLE " .. name)
    if not ok then return nil, err end

    db.run("DELETE FROM _collections WHERE name = ?", { name })
    schema_cache[name] = nil
    return true
end

-- records --

function collections.list_records(name, query_string, rule_opts)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local opts = query.parse(query_string, collection.schema)

    if opts.filter_error then return nil, opts.filter_error end
    if opts.sort_error then return nil, opts.sort_error end
    if opts.expand_error then return nil, opts.expand_error end

    if rule_opts then
        opts.rule_filter_sql = rule_opts.sql
        opts.rule_filter_params = rule_opts.params
    end

    local built = query.build_sql(name, opts)

    local records = db.query(built.sql, built.params)
    if not records then return nil, "query failed" end

    -- process expand --
    if opts.expand and #records > 0 then records = expand.process(records, opts.expand, name, collections.get, 0) end

    local result = {
        page = opts.page,
        perPage = opts.per_page,
        items = records,
    }

    if not opts.skip_total and built.count_sql then
        local count_result = db.query(built.count_sql, built.count_params)
        if count_result and count_result[1] then
            local total = count_result[1].count or 0
            result.totalItems = total
            result.totalPages = math.ceil(total / opts.per_page)
        end
    end

    return result
end

function collections.list_records_simple(name, limit, offset)
    limit = limit or 100
    offset = offset or 0
    local sql = "SELECT * FROM " .. name .. " ORDER BY id DESC LIMIT ? OFFSET ?"
    return db.query(sql, { limit, offset })
end

function collections.get_record(name, id, expand_string)
    local rows = db.query("SELECT * FROM " .. name .. " WHERE id = ?", { id })
    if not rows or #rows == 0 then return nil end

    local record = rows[1]

    -- process expand if provided --
    if expand_string and expand_string ~= "" then
        local expand_tree = expand.parse(expand_string)
        if expand_tree then
            local records = expand.process({ record }, expand_tree, name, collections.get, 0)
            record = records[1]
        end
    end

    return record
end

---@diagnostic disable-next-line: unused-local
function collections.create_record(name, data, multipart_parts, _ctx)
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

    local sql
    if #insert_fields > 0 then
        sql = "INSERT INTO "
            .. name
            .. " ("
            .. table.concat(insert_fields, ", ")
            .. ") VALUES ("
            .. table.concat(placeholders, ", ")
            .. ")"
    else
        sql = "INSERT INTO " .. name .. " DEFAULT VALUES"
    end
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

    local record = collections.get_record(name, id)
    if record then realtime.broker.broadcast(name, "create", record, collection) end
    return record
end

---@diagnostic disable-next-line: unused-local
function collections.update_record(name, id, data, multipart_parts, _ctx)
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

    local record = collections.get_record(name, id)
    if record then realtime.broker.broadcast(name, "update", record, collection) end
    return record
end

---@diagnostic disable-next-line: unused-local
function collections.delete_record(name, id, _ctx)
    local collection = collections.get(name)
    if not collection then return nil, "collection not found" end

    local existing = collections.get_record(name, id)
    if not existing then return nil, "record not found" end

    realtime.broker.broadcast(name, "delete", { id = existing.id }, collection)

    local changes, err = db.run("DELETE FROM " .. name .. " WHERE id = ?", { id })
    if err then return nil, err end
    if changes == 0 then return nil, "record not found" end

    files.delete_record_files(name, id)

    return true
end

return collections
