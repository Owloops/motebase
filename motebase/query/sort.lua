local sort = {}

local SYSTEM_FIELDS = {
    id = true,
    created_at = true,
    updated_at = true,
}

function sort.parse(sort_str, schema)
    if not sort_str or sort_str == "" then return nil end

    local fields = {}
    local errors = {}

    for part in sort_str:gmatch("[^,]+") do
        part = part:match("^%s*(.-)%s*$")
        if part ~= "" then
            local dir = "ASC"
            local field = part

            if part:sub(1, 1) == "-" then
                dir = "DESC"
                field = part:sub(2)
            elseif part:sub(1, 1) == "+" then
                field = part:sub(2)
            end

            field = field:match("^%s*(.-)%s*$")

            if field == "" then
                errors[#errors + 1] = "empty field name"
            elseif not field:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                errors[#errors + 1] = "invalid field name: " .. field
            elseif not SYSTEM_FIELDS[field] and schema and not schema[field] then
                errors[#errors + 1] = "unknown field: " .. field
            else
                fields[#fields + 1] = { field = field, dir = dir }
            end
        end
    end

    if #errors > 0 then return nil, table.concat(errors, ", ") end

    return #fields > 0 and fields or nil
end

function sort.to_sql(parsed)
    if not parsed or #parsed == 0 then return "id DESC" end

    local parts = {}
    for i = 1, #parsed do
        parts[#parts + 1] = parsed[i].field .. " " .. parsed[i].dir
    end
    return table.concat(parts, ", ")
end

return sort
