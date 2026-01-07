local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local crypto = require("motebase.crypto")

local oauth = {}

-- config --

local providers = {
    google = {
        auth_url = "https://accounts.google.com/o/oauth2/v2/auth",
        token_url = "https://oauth2.googleapis.com/token",
        userinfo_url = "https://www.googleapis.com/oauth2/v2/userinfo",
        scopes = "openid email profile",
        client_id = os.getenv("MOTEBASE_OAUTH_GOOGLE_ID"),
        client_secret = os.getenv("MOTEBASE_OAUTH_GOOGLE_SECRET"),
    },
    github = {
        auth_url = "https://github.com/login/oauth/authorize",
        token_url = "https://github.com/login/oauth/access_token",
        userinfo_url = "https://api.github.com/user",
        scopes = "read:user user:email",
        client_id = os.getenv("MOTEBASE_OAUTH_GITHUB_ID"),
        client_secret = os.getenv("MOTEBASE_OAUTH_GITHUB_SECRET"),
    },
}

local redirect_url = os.getenv("MOTEBASE_OAUTH_REDIRECT_URL")

local pending_states = {}

local STATE_EXPIRY = 300

-- helpers --

local function generate_state()
    return crypto.to_hex(crypto.random_bytes(16))
end

local function url_encode(str)
    return str:gsub("([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function build_query(params)
    local parts = {}
    for k, v in pairs(params) do
        parts[#parts + 1] = url_encode(k) .. "=" .. url_encode(v)
    end
    return table.concat(parts, "&")
end

local function http_post(url, body, headers)
    local response_body = {}
    local result, code = http.request({
        url = url,
        method = "POST",
        headers = headers or {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Accept"] = "application/json",
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
    })

    if not result then return nil, "request failed" end

    local body_str = table.concat(response_body)
    local ok, data = pcall(cjson.decode, body_str)
    if not ok then return nil, "invalid json response" end

    return data, nil, code
end

local function http_get(url, headers)
    local response_body = {}
    local result, code = http.request({
        url = url,
        method = "GET",
        headers = headers,
        sink = ltn12.sink.table(response_body),
    })

    if not result then return nil, "request failed" end

    local body_str = table.concat(response_body)
    local ok, data = pcall(cjson.decode, body_str)
    if not ok then return nil, "invalid json response" end

    return data, nil, code
end

local function cleanup_expired_states()
    local now = os.time()
    for state, info in pairs(pending_states) do
        if now > info.expires then pending_states[state] = nil end
    end
end

-- public --

function oauth.configure(cfg)
    if cfg.redirect_url then redirect_url = cfg.redirect_url end
    if cfg.google_id then providers.google.client_id = cfg.google_id end
    if cfg.google_secret then providers.google.client_secret = cfg.google_secret end
    if cfg.github_id then providers.github.client_id = cfg.github_id end
    if cfg.github_secret then providers.github.client_secret = cfg.github_secret end
end

function oauth.is_enabled(provider_name)
    local p = providers[provider_name]
    return p and p.client_id and p.client_secret and redirect_url and true or false
end

function oauth.get_auth_url(provider_name)
    local p = providers[provider_name]
    if not p then return nil, "unknown provider" end
    if not p.client_id then return nil, "provider not configured" end
    if not redirect_url then return nil, "redirect_url not configured" end

    cleanup_expired_states()

    local state = generate_state()
    pending_states[state] = {
        provider = provider_name,
        expires = os.time() + STATE_EXPIRY,
    }

    local params = {
        client_id = p.client_id,
        redirect_uri = redirect_url .. "/" .. provider_name .. "/callback",
        response_type = "code",
        scope = p.scopes,
        state = state,
    }

    return p.auth_url .. "?" .. build_query(params), state
end

function oauth.exchange_code(provider_name, code, state)
    local p = providers[provider_name]
    if not p then return nil, "unknown provider" end

    if not state or not pending_states[state] then return nil, "invalid or expired state" end

    local state_info = pending_states[state]
    if state_info.provider ~= provider_name then return nil, "state provider mismatch" end

    pending_states[state] = nil

    if os.time() > state_info.expires then return nil, "state expired" end

    local body = build_query({
        client_id = p.client_id,
        client_secret = p.client_secret,
        code = code,
        redirect_uri = redirect_url .. "/" .. provider_name .. "/callback",
        grant_type = "authorization_code",
    })

    local data, err = http_post(p.token_url, body)
    if not data then return nil, err end
    if data.error then return nil, data.error_description or data.error end

    return data.access_token
end

function oauth.get_user_info(provider_name, access_token)
    local p = providers[provider_name]
    if not p then return nil, "unknown provider" end

    local headers = {
        ["Authorization"] = "Bearer " .. access_token,
        ["Accept"] = "application/json",
        ["User-Agent"] = "MoteBase",
    }

    local data, err = http_get(p.userinfo_url, headers)
    if not data then return nil, err end

    local email = data.email
    local name = data.name

    if provider_name == "github" and not email then
        local emails, emails_err = http_get("https://api.github.com/user/emails", headers)
        if emails then
            for i = 1, #emails do
                if emails[i].primary then
                    email = emails[i].email
                    break
                end
            end
        else
            return nil, emails_err or "failed to fetch github emails"
        end
    end

    if not email then return nil, "email not available" end

    return {
        email = email,
        name = name or "",
        provider = provider_name,
        provider_id = tostring(data.id or data.sub or ""),
    }
end

function oauth.list_providers()
    local result = {}
    for name, _ in pairs(providers) do
        if oauth.is_enabled(name) then result[#result + 1] = name end
    end
    if #result == 0 then return cjson.empty_array end
    return result
end

return oauth
