-- SHA-256 (MIT, John Schember)

local bit = require("motebase.crypto.bit")
local band, bor, bxor, bnot, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift

---@class sha256
---@field _H number[]
---@field _len number
---@field _data string
---@field digest_size number
---@field block_size number
local sha256 = {}
local sha256_mt = { __metatable = {}, __index = sha256 }

sha256.digest_size = 32
sha256.block_size = 64

local K = {
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
}

local function u32(x)
    return band(x, 0xFFFFFFFF)
end

local function rotate_right(x, n)
    return u32(bor(rshift(x, n), lshift(x, 32 - n)))
end

local function CH(x, y, z)
    return bxor(band(x, y), band(bnot(x), z))
end

local function MAJ(x, y, z)
    return bxor(bxor(band(x, y), band(x, z)), band(y, z))
end

local function BSIG0(x)
    return bxor(bxor(rotate_right(x, 2), rotate_right(x, 13)), rotate_right(x, 22))
end

local function BSIG1(x)
    return bxor(bxor(rotate_right(x, 6), rotate_right(x, 11)), rotate_right(x, 25))
end

local function SSIG0(x)
    return bxor(bxor(rotate_right(x, 7), rotate_right(x, 18)), rshift(x, 3))
end

local function SSIG1(x)
    return bxor(bxor(rotate_right(x, 17), rotate_right(x, 19)), rshift(x, 10))
end

local function u32_to_bytes(x)
    return string.char(band(rshift(x, 24), 0xFF), band(rshift(x, 16), 0xFF), band(rshift(x, 8), 0xFF), band(x, 0xFF))
end

function sha256:new(data)
    if self ~= sha256 then return nil, "First argument must be self" end
    local o = setmetatable({}, sha256_mt)

    o._H = {
        0x6A09E667,
        0xBB67AE85,
        0x3C6EF372,
        0xA54FF53A,
        0x510E527F,
        0x9B05688C,
        0x1F83D9AB,
        0x5BE0CD19,
    }
    o._len = 0
    o._data = ""

    if data ~= nil then o:update(data) end

    return o
end
setmetatable(sha256, { __call = sha256.new })

function sha256:copy()
    local o = sha256:new() --[[@as sha256]]
    for i = 1, 8 do
        o._H[i] = self._H[i]
    end
    o._data = self._data
    o._len = self._len
    return o
end

function sha256:update(data)
    if data == nil then data = "" end

    data = tostring(data)
    self._len = self._len + #data
    self._data = self._data .. data

    while #self._data >= 64 do
        local W = {}
        for i = 1, 16 do
            local j = (i - 1) * 4 + 1
            W[i] = bor(
                bor(lshift(string.byte(self._data, j), 24), lshift(string.byte(self._data, j + 1), 16)),
                bor(lshift(string.byte(self._data, j + 2), 8), string.byte(self._data, j + 3))
            )
        end
        self._data = self._data:sub(65)

        for i = 17, 64 do
            W[i] = u32(SSIG1(W[i - 2]) + W[i - 7] + SSIG0(W[i - 15]) + W[i - 16])
        end

        local a, b, c, d, e, f, g, h =
            self._H[1], self._H[2], self._H[3], self._H[4], self._H[5], self._H[6], self._H[7], self._H[8]

        for i = 1, 64 do
            local temp1 = u32(h + BSIG1(e) + CH(e, f, g) + K[i] + W[i])
            local temp2 = u32(BSIG0(a) + MAJ(a, b, c))
            h = g
            g = f
            f = e
            e = u32(d + temp1)
            d = c
            c = b
            b = a
            a = u32(temp1 + temp2)
        end

        self._H[1] = u32(self._H[1] + a)
        self._H[2] = u32(self._H[2] + b)
        self._H[3] = u32(self._H[3] + c)
        self._H[4] = u32(self._H[4] + d)
        self._H[5] = u32(self._H[5] + e)
        self._H[6] = u32(self._H[6] + f)
        self._H[7] = u32(self._H[7] + g)
        self._H[8] = u32(self._H[8] + h)
    end
end

function sha256:digest()
    local final = self:copy() --[[@as sha256]]

    local padlen = final._len % 64
    if padlen < 56 then
        padlen = 56 - padlen
    else
        padlen = 120 - padlen
    end

    local len = final._len * 8
    local padding = string.char(0x80)
        .. string.rep("\0", padlen - 1)
        .. string.char(
            band(rshift(len, 56), 0xFF),
            band(rshift(len, 48), 0xFF),
            band(rshift(len, 40), 0xFF),
            band(rshift(len, 32), 0xFF),
            band(rshift(len, 24), 0xFF),
            band(rshift(len, 16), 0xFF),
            band(rshift(len, 8), 0xFF),
            band(len, 0xFF)
        )

    final:update(padding)

    return u32_to_bytes(final._H[1])
        .. u32_to_bytes(final._H[2])
        .. u32_to_bytes(final._H[3])
        .. u32_to_bytes(final._H[4])
        .. u32_to_bytes(final._H[5])
        .. u32_to_bytes(final._H[6])
        .. u32_to_bytes(final._H[7])
        .. u32_to_bytes(final._H[8])
end

function sha256:hexdigest()
    local h = self:digest()
    local out = {}
    for i = 1, #h do
        out[i] = string.format("%02x", string.byte(h, i))
    end
    return table.concat(out)
end

return sha256
