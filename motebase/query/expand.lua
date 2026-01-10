local lpeg = require("lpeg")
local db = require("motebase.db")
local cjson = require("cjson")

local expand = {}

local MAX_DEPTH = 6

local P, R, S = lpeg.P, lpeg.R, lpeg.S
local C, Ct = lpeg.C, lpeg.Ct

local ws = S(" \t") ^ 0
local alpha = R("az", "AZ")
local alnum = R("az", "AZ", "09")
local identifier = C((alpha + P("_")) * (alnum + P("_")) ^ 0)

local via_pattern = P({
    "backrel",
    backrel = C((alnum + P("_") - P("_via_")) ^ 1) * P("_via_") * C((alnum + P("_")) ^ 1),
}) / function(target, via_field)
    return { field = target, via = via_field, back_relation = true }
end

local function build_nested(field, nested)
    if nested then return { field = field, nested = nested } end
    return { field = field }
end

local forward_relation = P({
    "path",
    path = (identifier * (P(".") * lpeg.V("path")) ^ -1) / build_nested,
})

local expand_item = via_pattern + forward_relation

local expand_list = Ct(ws * expand_item * (ws * P(",") * ws * expand_item) ^ 0 * ws)

function expand.parse(expand_str)
    if not expand_str or expand_str == "" then return nil end

    local result = expand_list:match(expand_str)
    if not result then return nil, "invalid expand syntax" end

    return result
end

local function normalize_id(id)
    local n = tonumber(id)
    if n and n == math.floor(n) then return tostring(math.floor(n)) end
    return tostring(id)
end

function expand.fetch_and_index(ids, collection_name)
    if #ids == 0 then return {} end

    local normalized = {}
    for i = 1, #ids do
        normalized[i] = tonumber(ids[i]) or ids[i]
    end

    local placeholders = {}
    for i = 1, #normalized do
        placeholders[i] = "?"
    end

    local sql = "SELECT * FROM " .. collection_name .. " WHERE id IN (" .. table.concat(placeholders, ",") .. ")"

    local rows = db.query(sql, normalized)
    if not rows then return {} end

    local index = {}
    for _, row in ipairs(rows) do
        index[normalize_id(row.id)] = row
    end

    return index
end

local function resolve_target_collection(field_def)
    if field_def.collectionId then
        local rows = db.query("SELECT name FROM _collections WHERE id = ?", { field_def.collectionId })
        return rows and rows[1] and rows[1].name or nil
    end
    return field_def.collection
end

local function process_forward(records, node, schema, get_collection, depth)
    local field_def = schema[node.field]
    if not field_def or field_def.type ~= "relation" then
        return -- skip non-relation fields silently
    end

    local target_collection = resolve_target_collection(field_def)
    if not target_collection then return end

    local is_multiple = field_def.multiple

    local all_ids = {}
    local id_set = {}

    for _, record in ipairs(records) do
        local value = record[node.field]
        if value and value ~= "" then
            if is_multiple then
                local ids = type(value) == "table" and value or cjson.decode(value)
                for _, id in ipairs(ids or {}) do
                    local id_str = tostring(id)
                    if not id_set[id_str] then
                        id_set[id_str] = true
                        all_ids[#all_ids + 1] = id
                    end
                end
            else
                local id_str = tostring(value)
                if not id_set[id_str] then
                    id_set[id_str] = true
                    all_ids[#all_ids + 1] = value
                end
            end
        end
    end

    if #all_ids == 0 then return end

    local related_map = expand.fetch_and_index(all_ids, target_collection)

    if node.nested then
        local target_col = get_collection(target_collection)
        if target_col then
            local related_records = {}
            for _, record in pairs(related_map) do
                related_records[#related_records + 1] = record
            end
            expand.process(related_records, { node.nested }, target_collection, get_collection, depth + 1)
        end
    end

    for _, record in ipairs(records) do
        local value = record[node.field]
        if value and value ~= "" then
            record.expand = record.expand or {}
            if is_multiple then
                local ids = type(value) == "table" and value or cjson.decode(value)
                local expanded = {}
                for _, id in ipairs(ids or {}) do
                    local related = related_map[normalize_id(id)]
                    if related then expanded[#expanded + 1] = related end
                end
                record.expand[node.field] = expanded
            else
                record.expand[node.field] = related_map[normalize_id(value)]
            end
        end
    end
end

local function process_back_relation(records, node, get_collection)
    local target_collection = node.field
    local via_field = node.via

    local target_col = get_collection(target_collection)
    if not target_col then return end

    local source_ids = {}
    for _, record in ipairs(records) do
        source_ids[#source_ids + 1] = record.id
    end

    if #source_ids == 0 then return end

    local placeholders = {}
    for i = 1, #source_ids do
        placeholders[i] = "?"
    end

    local sql = "SELECT * FROM "
        .. target_collection
        .. " WHERE CAST("
        .. via_field
        .. " AS INTEGER) IN ("
        .. table.concat(placeholders, ",")
        .. ")"

    local related = db.query(sql, source_ids)
    if not related then return end

    local grouped = {}
    for _, row in ipairs(related) do
        local fk = normalize_id(row[via_field])
        grouped[fk] = grouped[fk] or {}
        grouped[fk][#grouped[fk] + 1] = row
    end

    local expand_key = target_collection .. "_via_" .. via_field
    for _, record in ipairs(records) do
        record.expand = record.expand or {}
        record.expand[expand_key] = grouped[normalize_id(record.id)] or {}
    end
end

function expand.process(records, expand_tree, source_collection, get_collection, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return records end
    if not expand_tree or #expand_tree == 0 then return records end
    if not records or #records == 0 then return records end

    local collection = get_collection(source_collection)
    if not collection then return records end

    for _, node in ipairs(expand_tree) do
        if node.back_relation then
            process_back_relation(records, node, get_collection)
        else
            process_forward(records, node, collection.schema, get_collection, depth)
        end
    end

    return records
end

return expand
