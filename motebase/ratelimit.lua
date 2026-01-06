local ratelimit = {}

local buckets = {}
local config = {}
local global_limit = nil

local DEFAULT_CONFIG = {
    ["/api/auth/login"] = { max = 10, window = 60 },
    ["/api/auth/register"] = { max = 5, window = 60 },
    ["*"] = { max = 100, window = 60 },
}

local function get_bucket_key(ip, path)
    return ip .. ":" .. path
end

local function get_config_for_path(path)
    if global_limit then return { max = global_limit, window = 60 } end
    if config[path] then return config[path] end
    if DEFAULT_CONFIG[path] then return DEFAULT_CONFIG[path] end
    return config["*"] or DEFAULT_CONFIG["*"]
end

local function get_or_create_bucket(key, cfg)
    local now = os.time()
    local bucket = buckets[key]

    if not bucket then
        bucket = {
            tokens = cfg.max,
            last_refill = now,
        }
        buckets[key] = bucket
    end

    local elapsed = now - bucket.last_refill
    if elapsed > 0 then
        local refill_rate = cfg.max / cfg.window
        local new_tokens = bucket.tokens + (elapsed * refill_rate)
        bucket.tokens = math.min(cfg.max, new_tokens)
        bucket.last_refill = now
    end

    return bucket
end

function ratelimit.configure(cfg)
    config = cfg or DEFAULT_CONFIG
end

function ratelimit.set_global_limit(limit)
    global_limit = limit
end

function ratelimit.is_enabled()
    return global_limit ~= 0
end

function ratelimit.check(ip, path)
    if global_limit == 0 then return true end

    local cfg = get_config_for_path(path)
    local key = get_bucket_key(ip, path)
    local bucket = get_or_create_bucket(key, cfg)

    if bucket.tokens >= 1 then
        bucket.tokens = bucket.tokens - 1
        return true
    end

    return false
end

function ratelimit.reset()
    buckets = {}
end

function ratelimit.cleanup()
    local now = os.time()
    local stale_threshold = 300

    for key, bucket in pairs(buckets) do
        if now - bucket.last_refill > stale_threshold then buckets[key] = nil end
    end
end

return ratelimit
