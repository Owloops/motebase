local email_parser = require("motebase.parser.email")

local schema = {}

local validators = {
    string = function(value)
        if type(value) ~= "string" then return nil, "expected string" end
        return value
    end,

    number = function(value)
        if type(value) == "number" then return value end
        local n = tonumber(value)
        if not n then return nil, "expected number" end
        return n
    end,

    boolean = function(value)
        if type(value) == "boolean" then return value end
        if value == "true" or value == 1 then return true end
        if value == "false" or value == 0 then return false end
        return nil, "expected boolean"
    end,

    email = function(value)
        if type(value) ~= "string" then return nil, "expected string" end
        return email_parser.validate(value)
    end,

    text = function(value)
        if type(value) ~= "string" then return nil, "expected string" end
        return value
    end,

    json = function(value)
        if type(value) == "table" then return value end
        return nil, "expected object"
    end,

    file = function(value)
        if value == nil then return nil end
        if type(value) == "table" and value.filename and value.size then return value end
        if type(value) == "string" then return value end
        return nil, "invalid file"
    end,

    relation = function(value, field_def)
        if value == nil then return nil end

        local function normalize_id(id)
            local n = tonumber(id)
            if n and n == math.floor(n) then return tostring(math.floor(n)) end
            return tostring(id)
        end

        local multiple = field_def and field_def.multiple

        if multiple then
            if type(value) ~= "table" then return nil, "expected array of IDs" end
            for i, id in ipairs(value) do
                if type(id) ~= "string" and type(id) ~= "number" then return nil, "invalid ID at index " .. i end
            end
            return value
        else
            if type(value) ~= "string" and type(value) ~= "number" then return nil, "expected ID string or number" end
            return normalize_id(value)
        end
    end,
}

function schema.validate_field(value, field_type, required, field_def)
    if value == nil then
        if required then return nil, "field is required" end
        return nil
    end

    local validator = validators[field_type]
    if not validator then return nil, "unknown field type: " .. field_type end

    return validator(value, field_def)
end

function schema.validate(data, fields)
    local errors = {}
    local validated = {}

    for name, def in pairs(fields) do
        if type(def) ~= "table" then
            errors[name] = "invalid field definition"
        else
            local field_type = def.type or "string"
            local required = def.required or false

            local value, err = schema.validate_field(data[name], field_type, required, def)
            if err then
                errors[name] = err
            else
                validated[name] = value
            end
        end
    end

    if next(errors) then return nil, errors end
    return validated
end

function schema.field_to_sql_type(field_type)
    local types = {
        string = "TEXT",
        text = "TEXT",
        email = "TEXT",
        number = "REAL",
        boolean = "INTEGER",
        json = "TEXT",
        file = "TEXT",
        relation = "TEXT", -- stores ID (single) or JSON array (multiple)
    }
    return types[field_type] or "TEXT"
end

function schema.is_relation_field(field_def)
    return field_def and field_def.type == "relation"
end

return schema
