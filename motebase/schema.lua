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
}

function schema.validate_field(value, field_type, required)
    if value == nil then
        if required then return nil, "field is required" end
        return nil
    end

    local validator = validators[field_type]
    if not validator then return nil, "unknown field type: " .. field_type end

    return validator(value)
end

function schema.validate(data, fields)
    local errors = {}
    local validated = {}

    for name, def in pairs(fields) do
        local field_type = def.type or "string"
        local required = def.required or false

        local value, err = schema.validate_field(data[name], field_type, required)
        if err then
            errors[name] = err
        else
            validated[name] = value
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
    }
    return types[field_type] or "TEXT"
end

return schema
