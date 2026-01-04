local lpeg = require("lpeg")

local filter = {}

-- primitives --

local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Cc = lpeg.C, lpeg.Cc

local ws = S(" \t\n\r") ^ 0
local digit = R("09")
local alpha = R("az", "AZ")

-- constants --

local SYSTEM_FIELDS = {
    id = true,
    created_at = true,
    updated_at = true,
}

local OP_MAP = {
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

-- tokens --

local function T(p)
    return p * ws
end

local number = T(C(P("-") ^ -1 * digit ^ 1 * (P(".") * digit ^ 1) ^ -1) / tonumber)

local string_sq = P("'") * C((P("\\'") + (1 - P("'"))) ^ 0) * P("'")
local string_dq = P('"') * C((P('\\"') + (1 - P('"'))) ^ 0) * P('"')
local string_lit = T(string_sq + string_dq)

local boolean_true = T(P("true")) * Cc(true)
local boolean_false = T(P("false")) * Cc(false)
local null = T(P("null")) * Cc(nil)

local identifier = T(C((alpha + P("_")) * (alpha + digit + P("_")) ^ 0))

local value = number + string_lit + boolean_true + boolean_false + null

-- operators --

local op_neq = T(P("!=")) * Cc("!=")
local op_gte = T(P(">=")) * Cc(">=")
local op_lte = T(P("<=")) * Cc("<=")
local op_gt = T(P(">")) * Cc(">")
local op_lt = T(P("<")) * Cc("<")
local op_eq = T(P("=")) * Cc("=")
local op_nlike = T(P("!~")) * Cc("!~")
local op_like = T(P("~")) * Cc("~")

local op_any_neq = T(P("?!=")) * Cc("?!=")
local op_any_gte = T(P("?>=")) * Cc("?>=")
local op_any_lte = T(P("?<=")) * Cc("?<=")
local op_any_gt = T(P("?>")) * Cc("?>")
local op_any_lt = T(P("?<")) * Cc("?<")
local op_any_eq = T(P("?=")) * Cc("?=")
local op_any_nlike = T(P("?!~")) * Cc("?!~")
local op_any_like = T(P("?~")) * Cc("?~")

local op_cmp = op_any_neq
    + op_any_gte
    + op_any_lte
    + op_any_gt
    + op_any_lt
    + op_any_eq
    + op_any_nlike
    + op_any_like
    + op_neq
    + op_gte
    + op_lte
    + op_gt
    + op_lt
    + op_eq
    + op_nlike
    + op_like

local op_and = T(P("&&")) * Cc("AND")
local op_or = T(P("||")) * Cc("OR")

-- ast builders --

local function build_comparison(field, op, val)
    return { type = "comparison", field = field, op = op, value = val }
end

local function fold_left(first, ...)
    local args = { ... }
    if #args == 0 then return first end

    local result = first
    for i = 1, #args, 2 do
        local op = args[i]
        local right = args[i + 1]
        if op and right then result = { type = "binary", op = op, left = result, right = right } end
    end
    return result
end

-- grammar --

local grammar = P({
    "filter",
    filter = ws * V("or_expr") * (P(-1) + P(";")),

    or_expr = (V("and_expr") * (op_or * V("and_expr")) ^ 0) / fold_left,
    and_expr = (V("primary") * (op_and * V("primary")) ^ 0) / fold_left,

    primary = T(P("(")) * V("or_expr") * T(P(")")) + V("comparison"),

    comparison = identifier * op_cmp * value / build_comparison,
})

-- public --

function filter.parse(filter_str)
    if not filter_str or filter_str == "" then return nil, "empty filter" end

    local ast = grammar:match(filter_str)
    if not ast then return nil, "invalid filter syntax" end

    return ast
end

function filter.validate(ast, schema)
    if not ast then return nil end

    local function check_node(node)
        if node.type == "comparison" then
            local field = node.field
            if not SYSTEM_FIELDS[field] and not schema[field] then return "unknown field: " .. field end
        elseif node.type == "binary" then
            local err = check_node(node.left)
            if err then return err end
            return check_node(node.right)
        end
        return nil
    end

    return check_node(ast)
end

function filter.to_sql(ast)
    if not ast then return nil, {} end

    local params = {}

    local function to_sql_node(node)
        if node.type == "comparison" then
            local sql_op = OP_MAP[node.op]
            local val = node.value

            if node.op == "~" or node.op == "?~" then
                if type(val) == "string" and not val:find("%%") then val = "%" .. val .. "%" end
            elseif node.op == "!~" or node.op == "?!~" then
                if type(val) == "string" and not val:find("%%") then val = "%" .. val .. "%" end
            end

            params[#params + 1] = val
            return node.field .. " " .. sql_op .. " ?"
        elseif node.type == "binary" then
            local left_sql = to_sql_node(node.left)
            local right_sql = to_sql_node(node.right)
            return "(" .. left_sql .. " " .. node.op .. " " .. right_sql .. ")"
        end

        return "1=1"
    end

    local sql = to_sql_node(ast)
    return sql, params
end

return filter
