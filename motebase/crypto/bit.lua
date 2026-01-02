local bit

if _VERSION >= "Lua 5.3" then
    bit = {
        band = function(a, b)
            return a & b
        end,
        bor = function(a, b)
            return a | b
        end,
        bxor = function(a, b)
            return a ~ b
        end,
        bnot = function(a)
            return ~a
        end,
        lshift = function(a, n)
            return a << n
        end,
        rshift = function(a, n)
            return a >> n
        end,
    }
elseif rawget(_G, "jit") then
    bit = require("bit")
else
    local ok, lib = pcall(require, "bit32")
    if not ok then
        ok, lib = pcall(require, "bit")
    end
    if ok then
        bit = {
            band = lib.band,
            bor = lib.bor,
            bxor = lib.bxor,
            bnot = lib.bnot,
            lshift = lib.lshift,
            rshift = lib.rshift,
        }
    else
        error("no bitwise library available")
    end
end

return bit
