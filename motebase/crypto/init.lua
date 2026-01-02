local sha256 = require("motebase.crypto.sha256")
local hmac = require("motebase.crypto.hmac")
local bit = require("motebase.crypto.bit")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local byte, char, format, rep = string.byte, string.char, string.format, string.rep
local concat = table.concat

local crypto = {}

function crypto.sha256(message)
    return sha256(message):digest()
end

function crypto.hmac_sha256(key, message)
    return hmac(sha256, key, message):digest()
end

function crypto.to_hex(data)
    local out = {}
    for i = 1, #data do
        out[i] = format("%02x", byte(data, i))
    end
    return concat(out)
end

-- base64 --

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, 64 do
    b64lookup[b64chars:sub(i, i)] = i - 1
end

function crypto.base64_encode(data)
    local result = {}
    local mod = #data % 3
    if mod > 0 then data = data .. rep("\0", 3 - mod) end
    for i = 1, #data, 3 do
        local n = bor(bor(lshift(byte(data, i), 16), lshift(byte(data, i + 1), 8)), byte(data, i + 2))
        result[#result + 1] = b64chars:sub(rshift(n, 18) + 1, rshift(n, 18) + 1)
            .. b64chars:sub(band(rshift(n, 12), 63) + 1, band(rshift(n, 12), 63) + 1)
            .. b64chars:sub(band(rshift(n, 6), 63) + 1, band(rshift(n, 6), 63) + 1)
            .. b64chars:sub(band(n, 63) + 1, band(n, 63) + 1)
    end
    local encoded = concat(result)
    if mod > 0 then encoded = encoded:sub(1, -(3 - mod) - 1) .. rep("=", 3 - mod) end
    return encoded
end

function crypto.base64_decode(data)
    data = data:gsub("%s", ""):gsub("=", "")
    local pad = (4 - #data % 4) % 4
    data = data .. rep("A", pad)
    local result = {}
    for i = 1, #data, 4 do
        local n = bor(
            bor(lshift(b64lookup[data:sub(i, i)], 18), lshift(b64lookup[data:sub(i + 1, i + 1)], 12)),
            bor(lshift(b64lookup[data:sub(i + 2, i + 2)], 6), b64lookup[data:sub(i + 3, i + 3)])
        )
        result[#result + 1] = char(band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF))
    end
    local decoded = concat(result)
    return pad > 0 and decoded:sub(1, -pad - 1) or decoded
end

function crypto.base64url_encode(data)
    return crypto.base64_encode(data):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

function crypto.base64url_decode(data)
    local b64 = data:gsub("-", "+"):gsub("_", "/")
    local pad = (4 - #b64 % 4) % 4
    if pad > 0 and pad < 4 then b64 = b64 .. rep("=", pad) end
    return crypto.base64_decode(b64)
end

local bxor = bit.bxor

function crypto.constant_time_compare(a, b)
    if #a ~= #b then return false end
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(byte(a, i), byte(b, i)))
    end
    return result == 0
end

function crypto.random_bytes(n)
    local f = io.open("/dev/urandom", "rb")
    if not f then error("cannot open /dev/urandom") end
    local bytes = f:read(n)
    f:close()
    if not bytes or #bytes ~= n then error("failed to read from /dev/urandom") end
    return bytes
end

return crypto
