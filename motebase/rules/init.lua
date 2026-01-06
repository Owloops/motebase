local parser = require("motebase.rules.parser")
local eval = require("motebase.rules.eval")

local rules = {
    parse = parser.parse,
    is_valid = parser.is_valid,
    check = eval.check,
    to_sql_filter = eval.to_sql_filter,
    extract_auth_conditions = eval.extract_auth_conditions,
    extract_record_conditions = eval.extract_record_conditions,
}

return rules
