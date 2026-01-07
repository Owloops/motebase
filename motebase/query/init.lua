local filter = require("motebase.query.filter")
local sort = require("motebase.query.sort")
local expand = require("motebase.query.expand")
local url_util = require("motebase.utils.url")

local unpack = table.unpack or unpack

local query = {}

local DEFAULT_PAGE = 1
local DEFAULT_PER_PAGE = 20
local MAX_PER_PAGE = 500

local SYSTEM_FIELDS = {
    id = true,
    created_at = true,
    updated_at = true,
}

local function parse_int(str, default)
    if not str then return default end
    local n = tonumber(str)
    if not n then return default end
    return math.floor(n)
end

local function parse_fields(fields_str)
    if not fields_str or fields_str == "" then return nil end
    local fields = {}
    for field in fields_str:gmatch("[^,]+") do
        field = field:match("^%s*(.-)%s*$")
        if field ~= "" then fields[#fields + 1] = field end
    end
    return #fields > 0 and fields or nil
end

local function validate_fields(fields, schema)
    if not fields then return nil end
    local valid = {}
    for i = 1, #fields do
        local field = fields[i]
        if SYSTEM_FIELDS[field] or (schema and schema[field]) then valid[#valid + 1] = field end
    end
    return #valid > 0 and valid or nil
end

function query.parse(query_string, schema)
    local params = url_util.parse_query(query_string)

    local page = parse_int(params.page, DEFAULT_PAGE)
    if page < 1 then page = 1 end

    local per_page = parse_int(params.perPage, DEFAULT_PER_PAGE)
    if per_page < 1 then per_page = 1 end
    if per_page > MAX_PER_PAGE then per_page = MAX_PER_PAGE end

    local skip_total = params.skipTotal == "true" or params.skipTotal == "1"

    local fields = parse_fields(params.fields)
    fields = validate_fields(fields, schema)

    local sort_list, sort_err = sort.parse(params.sort, schema)

    local filter_ast, filter_err
    if params.filter and params.filter ~= "" then
        filter_ast, filter_err = filter.parse(params.filter)
        if filter_ast and schema then
            local valid_err = filter.validate(filter_ast, schema)
            if valid_err then
                filter_ast = nil
                filter_err = valid_err
            end
        end
    end

    local expand_tree, expand_err
    if params.expand and params.expand ~= "" then
        expand_tree, expand_err = expand.parse(params.expand)
    end

    return {
        page = page,
        per_page = per_page,
        skip_total = skip_total,
        fields = fields,
        sort = sort_list,
        sort_error = sort_err,
        filter = filter_ast,
        filter_error = filter_err,
        expand = expand_tree,
        expand_error = expand_err,
    }
end

function query.build_sql(collection_name, opts)
    opts = opts or {}
    local params = {}

    local select_fields = "*"
    if opts.fields and #opts.fields > 0 then select_fields = table.concat(opts.fields, ", ") end

    local where_parts = {}

    if opts.filter then
        local where, where_params = filter.to_sql(opts.filter)
        if where then
            where_parts[#where_parts + 1] = where
            for i = 1, #where_params do
                params[#params + 1] = where_params[i]
            end
        end
    end

    if opts.rule_filter_sql then
        where_parts[#where_parts + 1] = opts.rule_filter_sql
        if opts.rule_filter_params then
            for i = 1, #opts.rule_filter_params do
                params[#params + 1] = opts.rule_filter_params[i]
            end
        end
    end

    local where_clause = ""
    if #where_parts > 0 then where_clause = " WHERE " .. table.concat(where_parts, " AND ") end

    local order_clause
    if opts.sort and #opts.sort > 0 then
        order_clause = " ORDER BY " .. sort.to_sql(opts.sort)
    else
        order_clause = " ORDER BY id DESC"
    end

    local limit = opts.per_page or DEFAULT_PER_PAGE
    local offset = ((opts.page or 1) - 1) * limit

    local sql = "SELECT "
        .. select_fields
        .. " FROM "
        .. collection_name
        .. where_clause
        .. order_clause
        .. " LIMIT ? OFFSET ?"

    params[#params + 1] = limit
    params[#params + 1] = offset

    local count_sql = nil
    local count_params = {}
    if not opts.skip_total then
        count_sql = "SELECT COUNT(*) as count FROM " .. collection_name .. where_clause
        if #params > 2 then count_params = { unpack(params, 1, #params - 2) } end
    end

    return {
        sql = sql,
        count_sql = count_sql,
        params = params,
        count_params = count_params,
    }
end

return query
