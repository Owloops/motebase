local url = {}

local function char_to_pchar(c)
    return string.format("%%%02X", c:byte(1, 1))
end

function url.encode(str)
    return (str:gsub("[^%w%-_%.%!%~%*%'%(%)]", char_to_pchar))
end

function url.encode_uri(str)
    return (str:gsub("[^%;%,%/%?%:%@%&%=%+%$%w%-%_%.%!%~%*%'%(%)%#]", char_to_pchar))
end

local function pchar_to_char(hex)
    return string.char(tonumber(hex, 16))
end

function url.decode(str)
    return (str:gsub("%%(%x%x)", pchar_to_char))
end

local decode_uri_blacklist = {}
for char in ("#$&+,/:;=?@"):gmatch(".") do
    decode_uri_blacklist[string.byte(char)] = true
end

function url.decode_uri(str)
    return (
        str:gsub("%%(%x%x)", function(hex)
            local x = tonumber(hex, 16)
            if not decode_uri_blacklist[x] then return string.char(x) end
        end)
    )
end

function url.parse_query(query_string)
    if not query_string or query_string == "" then return {} end

    local params = {}
    for pair in query_string:gmatch("[^&]+") do
        local eq_pos = pair:find("=")
        if eq_pos then
            local key = url.decode(pair:sub(1, eq_pos - 1):gsub("+", " "))
            local value = url.decode(pair:sub(eq_pos + 1):gsub("+", " "))
            params[key] = value
        else
            params[url.decode(pair:gsub("+", " "))] = ""
        end
    end
    return params
end

function url.build_query(params)
    local parts, i = {}, 0
    for key, value in pairs(params) do
        i = i + 1
        parts[i] = url.encode(key) .. "=" .. url.encode(value)
    end
    return table.concat(parts, "&")
end

return url
