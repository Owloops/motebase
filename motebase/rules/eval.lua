local eval = {}

-- helpers --

local function normalize_for_comparison(a, b)
    if type(a) == type(b) then return a, b end

    if type(a) == "number" and type(b) == "string" then
        local num_b = tonumber(b)
        if num_b then return a, num_b end
        return tostring(a), b
    end

    if type(a) == "string" and type(b) == "number" then
        local num_a = tonumber(a)
        if num_a then return num_a, b end
        return a, tostring(b)
    end

    return a, b
end

-- operators --

local OP_FN = {
    ["="] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na == nb
    end,
    ["!="] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na ~= nb
    end,
    [">"] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na > nb
    end,
    [">="] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na >= nb
    end,
    ["<"] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na < nb
    end,
    ["<="] = function(a, b)
        local na, nb = normalize_for_comparison(a, b)
        return na <= nb
    end,
    ["~"] = function(a, b)
        if type(a) ~= "string" or type(b) ~= "string" then return false end
        local pattern = b:gsub("%%", "%%%%")
        if not pattern:find("%%") then
            pattern = ".*" .. pattern:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") .. ".*"
        else
            pattern = "^" .. pattern:gsub("%%", ".*") .. "$"
        end
        return a:lower():match(pattern:lower()) ~= nil
    end,
    ["!~"] = function(a, b)
        if type(a) ~= "string" or type(b) ~= "string" then return true end
        local pattern = b:gsub("%%", "%%%%")
        if not pattern:find("%%") then
            pattern = ".*" .. pattern:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") .. ".*"
        else
            pattern = "^" .. pattern:gsub("%%", ".*") .. "$"
        end
        return a:lower():match(pattern:lower()) == nil
    end,
}

local OP_SQL = {
    ["="] = "=",
    ["!="] = "!=",
    [">"] = ">",
    [">="] = ">=",
    ["<"] = "<",
    ["<="] = "<=",
    ["~"] = "LIKE",
    ["!~"] = "NOT LIKE",
    ["?="] = "=",
    ["?!="] = "!=",
    ["?>"] = ">",
    ["?>="] = ">=",
    ["?<"] = "<",
    ["?<="] = "<=",
    ["?~"] = "LIKE",
    ["?!~"] = "NOT LIKE",
}

-- datetime macros --

local function get_datetime_value(name)
    local now = os.time()
    local date = os.date("!*t", now)

    if name == "now" then
        return os.date("!%Y-%m-%d %H:%M:%S", now)
    elseif name == "second" then
        return date.sec
    elseif name == "minute" then
        return date.min
    elseif name == "hour" then
        return date.hour
    elseif name == "weekday" then
        return date.wday - 1
    elseif name == "day" then
        return date.day
    elseif name == "month" then
        return date.month
    elseif name == "year" then
        return date.year
    elseif name == "yesterday" then
        return os.date("!%Y-%m-%d %H:%M:%S", now - 86400)
    elseif name == "tomorrow" then
        return os.date("!%Y-%m-%d %H:%M:%S", now + 86400)
    elseif name == "todayStart" then
        local start = os.time({ year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 })
        return os.date("!%Y-%m-%d %H:%M:%S", start)
    elseif name == "todayEnd" then
        local end_time =
            os.time({ year = date.year, month = date.month, day = date.day, hour = 23, min = 59, sec = 59 })
        return os.date("!%Y-%m-%d %H:%M:%S", end_time)
    elseif name == "monthStart" then
        local start = os.time({ year = date.year, month = date.month, day = 1, hour = 0, min = 0, sec = 0 })
        return os.date("!%Y-%m-%d %H:%M:%S", start)
    elseif name == "monthEnd" then
        local next_month = os.time({ year = date.year, month = date.month + 1, day = 1, hour = 0, min = 0, sec = 0 })
        return os.date("!%Y-%m-%d %H:%M:%S", next_month - 1)
    elseif name == "yearStart" then
        local start = os.time({ year = date.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
        return os.date("!%Y-%m-%d %H:%M:%S", start)
    elseif name == "yearEnd" then
        local end_time = os.time({ year = date.year, month = 12, day = 31, hour = 23, min = 59, sec = 59 })
        return os.date("!%Y-%m-%d %H:%M:%S", end_time)
    end

    return nil
end

-- helpers --

local function resolve_path(obj, path)
    if not obj or not path then return nil end

    local current = obj
    for i = 1, #path do
        if type(current) ~= "table" then return nil end
        current = current[path[i]]
        if current == nil then return nil end
    end
    return current
end

local function apply_modifier(value, modifier, ctx, node)
    if not modifier then return value end

    if modifier == "isset" then
        return value ~= nil
    elseif modifier == "changed" then
        if not ctx.record then return value ~= nil end
        local path = node.path
        if path[1] == "body" then
            local field_name = path[#path]
            local old_value = ctx.record[field_name]
            return value ~= nil and value ~= old_value
        end
        return false
    elseif modifier == "length" then
        if type(value) == "table" then return #value end
        if type(value) == "string" then return #value end
        return 0
    elseif modifier == "lower" then
        if type(value) == "string" then return value:lower() end
        return value
    elseif modifier == "each" then
        return value
    end

    return value
end

local function resolve_value(node, ctx)
    if node.type == "literal" then
        return node.value
    elseif node.type == "macro" then
        return get_datetime_value(node.name)
    elseif node.type == "request" then
        local path = node.path
        if not path or #path == 0 then return nil end

        local category = path[1]
        local rest = {}
        for i = 2, #path do
            rest[#rest + 1] = path[i]
        end

        local value
        if category == "auth" then
            if #rest == 0 then
                value = ctx.auth
            else
                value = resolve_path(ctx.auth, rest)
            end
        elseif category == "body" then
            if #rest == 0 then
                value = ctx.body
            else
                value = resolve_path(ctx.body, rest)
            end
        elseif category == "query" then
            if #rest == 0 then
                value = ctx.query
            else
                value = resolve_path(ctx.query, rest)
            end
        elseif category == "headers" then
            if #rest == 0 then
                value = ctx.headers
            else
                local header_key = rest[1]
                if header_key then header_key = header_key:lower():gsub("-", "_") end
                if ctx.headers then value = ctx.headers[header_key] end
            end
        elseif category == "method" then
            value = ctx.method
        elseif category == "context" then
            value = ctx.context
        end

        return apply_modifier(value, node.modifier, ctx, node)
    elseif node.type == "field" then
        if ctx.record then return ctx.record[node.name] end
        return nil
    elseif node.type == "field_path" then
        local path = node.path
        if not path or #path == 0 then return nil end

        local value
        if ctx.record then
            if #path == 1 then
                value = ctx.record[path[1]]
            else
                value = resolve_path(ctx.record, path)
            end
        end

        return apply_modifier(value, node.modifier, ctx, node)
    end

    return nil
end

local function is_request_node(node)
    return node.type == "request"
end

local function is_record_field(node)
    return node.type == "field" or node.type == "field_path"
end

local function any_match(arr, op, val)
    if type(arr) ~= "table" then return false end
    local base_op = op:sub(2)
    local fn = OP_FN[base_op]
    if not fn then return false end

    for i = 1, #arr do
        if fn(arr[i], val) then return true end
    end
    return false
end

local function each_match(arr, op, val)
    if type(arr) ~= "table" then return false end
    if #arr == 0 then return false end

    local fn = OP_FN[op]
    if not fn then return false end

    for i = 1, #arr do
        if not fn(arr[i], val) then return false end
    end
    return true
end

-- evaluation --

local function eval_node(node, ctx)
    if node.type == "comparison" then
        local field_val = resolve_value(node.field, ctx)
        local cmp_val = resolve_value(node.value, ctx)
        local op = node.op

        local modifier = node.field.modifier

        if modifier == "each" then return each_match(field_val, op, cmp_val) end

        if op:sub(1, 1) == "?" then return any_match(field_val, op, cmp_val) end

        local fn = OP_FN[op]
        if not fn then return false end

        if field_val == nil then field_val = "" end
        if cmp_val == nil then cmp_val = "" end

        return fn(field_val, cmp_val)
    elseif node.type == "binary" then
        local left = eval_node(node.left, ctx)
        local right = eval_node(node.right, ctx)

        if node.op == "AND" then
            return left and right
        elseif node.op == "OR" then
            return left or right
        end
    end

    return false
end

function eval.check(ast, ctx)
    if not ast then return true end
    ctx = ctx or {}
    return eval_node(ast, ctx)
end

-- sql generation --

local function get_field_name(node)
    if node.type == "field" then
        return node.name
    elseif node.type == "field_path" then
        return node.path[1]
    end
    return nil
end

local function to_sql_node(node, ctx, params)
    if node.type == "comparison" then
        if not is_record_field(node.field) then return nil end

        if node.field.modifier then return nil end

        if node.field.type == "field_path" and #node.field.path > 1 then return nil end

        local field_name = get_field_name(node.field)
        local op = node.op
        local sql_op = OP_SQL[op]
        if not sql_op then return nil end

        local val = resolve_value(node.value, ctx)

        if op == "~" or op == "?~" then
            if type(val) == "string" and not val:find("%%") then val = "%" .. val .. "%" end
        elseif op == "!~" or op == "?!~" then
            if type(val) == "string" and not val:find("%%") then val = "%" .. val .. "%" end
        end

        params[#params + 1] = val
        return field_name .. " " .. sql_op .. " ?"
    elseif node.type == "binary" then
        local left_sql = to_sql_node(node.left, ctx, params)
        local right_sql = to_sql_node(node.right, ctx, params)

        if left_sql and right_sql then
            return "(" .. left_sql .. " " .. node.op .. " " .. right_sql .. ")"
        elseif left_sql then
            return left_sql
        elseif right_sql then
            return right_sql
        end
    end

    return nil
end

function eval.to_sql_filter(ast, ctx)
    if not ast then return nil, {} end

    ctx = ctx or {}
    local params = {}

    local sql = to_sql_node(ast, ctx, params)
    return sql, params
end

function eval.extract_auth_conditions(ast)
    if not ast then return nil end

    local function has_request_ref(node)
        if node.type == "comparison" then
            return is_request_node(node.field) or is_request_node(node.value)
        elseif node.type == "binary" then
            return has_request_ref(node.left) or has_request_ref(node.right)
        end
        return false
    end

    local function extract(node)
        if node.type == "comparison" then
            if has_request_ref(node) then return node end
            return nil
        elseif node.type == "binary" then
            local left = extract(node.left)
            local right = extract(node.right)

            if left and right then
                return { type = "binary", op = node.op, left = left, right = right }
            elseif left then
                return left
            elseif right then
                return right
            end
        end
        return nil
    end

    return extract(ast)
end

function eval.extract_record_conditions(ast)
    if not ast then return nil end

    local function is_record_only(node)
        if node.type == "comparison" then
            return is_record_field(node.field) and (node.value.type == "literal" or node.value.type == "macro")
        end
        return false
    end

    local function extract(node)
        if node.type == "comparison" then
            if is_record_only(node) then return node end
            return nil
        elseif node.type == "binary" then
            local left = extract(node.left)
            local right = extract(node.right)

            if left and right then
                return { type = "binary", op = node.op, left = left, right = right }
            elseif left then
                return left
            elseif right then
                return right
            end
        end
        return nil
    end

    return extract(ast)
end

return eval
