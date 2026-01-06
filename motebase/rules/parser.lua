local lpeg = require("lpeg")

local parser = {}

-- primitives --

local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Cc, Ct = lpeg.C, lpeg.Cc, lpeg.Ct

local line_comment = P("//") * (1 - P("\n")) ^ 0 * (P("\n") + P(-1))
local ws = (S(" \t\n\r") + line_comment) ^ 0
local digit = R("09")
local alpha = R("az", "AZ")

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

-- @request.* and @now --

local path_segment = C((alpha + digit + P("_")) ^ 1)
local path = Ct(path_segment * (P(".") * path_segment) ^ 0)

local datetime_macros = {
    "todayStart",
    "todayEnd",
    "monthStart",
    "monthEnd",
    "yearStart",
    "yearEnd",
    "yesterday",
    "tomorrow",
    "weekday",
    "second",
    "minute",
    "hour",
    "month",
    "year",
    "day",
    "now",
}

local at_macro
for i = 1, #datetime_macros do
    local name = datetime_macros[i]
    local p = T(P("@" .. name) * Cc({ type = "macro", name = name }))
    at_macro = at_macro and (at_macro + p) or p
end

local modifier = P(":") * C(P("isset") + P("changed") + P("length") + P("each") + P("lower"))

local at_request = T(P("@request.") * path * modifier ^ -1 / function(segments, mod)
    return { type = "request", path = segments, modifier = mod }
end)

local special = at_request + at_macro

local value = special + number + string_lit + boolean_true + boolean_false + null

local field_name = C((alpha + P("_")) * (alpha + digit + P("_")) ^ 0)
local field_path = T(Ct(field_name * (P(".") * field_name) ^ 0) * modifier ^ -1 / function(segments, mod)
    if #segments == 1 and not mod then return segments[1] end
    return { type = "field_path", path = segments, modifier = mod }
end)

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

local function build_comparison(left, op, right)
    local field, val

    if type(left) == "table" then
        field = left
    else
        field = { type = "field", name = left }
    end

    if type(right) == "table" and right.type then
        val = right
    elseif type(right) == "string" and right:sub(1, 1) == "@" then
        val = { type = "macro", name = right:sub(2) }
    else
        val = { type = "literal", value = right }
    end

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

local lhs = special + field_path

local grammar = P({
    "rule",
    rule = ws * V("or_expr") * (P(-1) + P(";")),

    or_expr = (V("and_expr") * (op_or * V("and_expr")) ^ 0) / fold_left,
    and_expr = (V("primary") * (op_and * V("primary")) ^ 0) / fold_left,

    primary = T(P("(")) * V("or_expr") * T(P(")")) + V("comparison"),

    comparison = lhs * op_cmp * value / build_comparison,
})

-- public --

function parser.parse(rule_str)
    if not rule_str or rule_str == "" then return nil end

    local ast = grammar:match(rule_str)
    if not ast then return nil, "invalid rule syntax" end

    return ast
end

function parser.is_valid(rule_str)
    if rule_str == nil then return true end
    if rule_str == "" then return true end

    local ast, err = parser.parse(rule_str)
    if not ast then return false, err end
    return true
end

return parser
