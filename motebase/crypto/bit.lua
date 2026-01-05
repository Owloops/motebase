local bit

if rawget(_G, "jit") then
    bit = require("bit")
elseif _VERSION >= "Lua 5.3" then
    bit = {
        band = load("return function(a, b) return a & b end")(),
        bor = load("return function(a, b) return a | b end")(),
        bxor = load("return function(a, b) return a ~ b end")(),
        bnot = load("return function(a) return ~a end")(),
        lshift = load("return function(a, n) return a << n end")(),
        rshift = load("return function(a, n) return a >> n end")(),
    }
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
