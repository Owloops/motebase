local bit = require("motebase.crypto.bit")
local bxor = bit.bxor

local hmac = {}
local hmac_mt = { __metatable = {}, __index = hmac }

function hmac:new(hash_module, key, data)
    if self ~= hmac then return nil, "First argument must be self" end
    local o = setmetatable({}, hmac_mt)
    o._hm = hash_module

    if #key > hash_module.block_size then
        local th = hash_module(key)
        key = th:digest()
    end

    local tk = {}
    for i = 1, #key do
        tk[i] = string.byte(key, i)
    end
    for i = #key + 1, hash_module.block_size do
        tk[i] = 0
    end

    local ipad_bytes = {}
    local opad_bytes = {}
    for i = 1, #tk do
        ipad_bytes[i] = string.char(bxor(tk[i], 0x36))
        opad_bytes[i] = string.char(bxor(tk[i], 0x5C))
    end
    local ipad = table.concat(ipad_bytes)
    o._opad = table.concat(opad_bytes)

    o._hash = o._hm(ipad)

    if data ~= nil then o._hash:update(data) end

    return o
end
setmetatable(hmac, { __call = hmac.new })

function hmac:copy()
    local o = setmetatable({}, hmac_mt)
    o._hm = self._hm
    o._hash = self._hash:copy()
    o._opad = self._opad
    return o
end

function hmac:update(data)
    self._hash:update(data)
end

function hmac:digest()
    local final = self:copy()
    local digest = final._hash:digest()
    local th = final._hm(final._opad)
    th:update(digest)
    return th:digest()
end

function hmac:hexdigest()
    local h = self:digest()
    local out = {}
    for i = 1, #h do
        out[i] = string.format("%02x", string.byte(h, i))
    end
    return table.concat(out)
end

return hmac
