local db = require("motebase.db")
local jwt = require("motebase.jwt")
local crypto = require("motebase.crypto")
local log = require("motebase.utils.log")
local email_parser = require("motebase.parser.email")
local mail = require("motebase.mail")

local auth = {}

local RESET_TOKEN_EXPIRY = 3600
local VERIFY_TOKEN_EXPIRY = 86400
local MIN_PASSWORD_LENGTH = 8

local superuser_email = nil

-- helpers --

local function generate_salt()
    return crypto.to_hex(crypto.random_bytes(16))
end

local function hash_password(password, salt)
    return crypto.to_hex(crypto.sha256(salt .. password))
end

local function generate_token()
    return crypto.to_hex(crypto.random_bytes(32))
end

local function current_timestamp()
    return os.time()
end

function auth.init()
    return db.exec([[
        CREATE TABLE IF NOT EXISTS _users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            verified INTEGER DEFAULT 0,
            reset_token TEXT,
            reset_token_expiry INTEGER,
            verify_token TEXT,
            verify_token_expiry INTEGER,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
end

function auth.register(email, password)
    if not email or not password then return nil, "email and password required" end

    if not email_parser.is_valid(email) then return nil, "invalid email format" end

    if #password < MIN_PASSWORD_LENGTH then
        return nil, "password must be at least " .. MIN_PASSWORD_LENGTH .. " characters"
    end

    local existing = db.query("SELECT id FROM _users WHERE email = ?", { email })
    if existing and #existing > 0 then
        log.auth_failure("email already registered", { email = email })
        return nil, "email already registered"
    end

    local salt = generate_salt()
    local password_hash = hash_password(password, salt)

    local id, err = db.insert(
        "INSERT INTO _users (email, password_hash, password_salt) VALUES (?, ?, ?)",
        { email, password_hash, salt }
    )
    if not id then return nil, err end

    log.info("auth", "user registered", { user_id = id, email = email })

    return { id = id, email = email }
end

function auth.login(email, password, secret, expires_in)
    if not email or not password then return nil, "email and password required" end

    local users = db.query("SELECT * FROM _users WHERE email = ?", { email })
    if not users or #users == 0 then
        log.auth_failure("user not found", { email = email })
        return nil, "invalid credentials"
    end

    local user = users[1]
    local password_hash = hash_password(password, user.password_salt)

    if not crypto.constant_time_compare(password_hash, user.password_hash) then
        log.auth_failure("invalid password", { user_id = user.id, email = email })
        return nil, "invalid credentials"
    end

    local token = jwt.create_token(user.id, secret, { expires_in = expires_in })

    log.auth_success(user.id, "password")

    return {
        token = token,
        user = {
            id = user.id,
            email = user.email,
        },
    }
end

function auth.get_user(user_id)
    local users = db.query("SELECT id, email, created_at FROM _users WHERE id = ?", { user_id })
    if not users or #users == 0 then return nil end
    return users[1]
end

-- superuser --

function auth.configure(opts)
    if opts then superuser_email = opts.superuser end
end

function auth.is_superuser(user)
    if not user then return false end

    local email = user.email
    if not email and user.sub then
        local u = auth.get_user(user.sub)
        email = u and u.email
    end

    if superuser_email then return email == superuser_email end

    local id = user.id or user.sub
    return id == 1
end

-- password reset --

function auth.request_password_reset(email_addr, app_url)
    if not email_addr then return nil, "email required" end

    local users = db.query("SELECT id, email FROM _users WHERE email = ?", { email_addr })
    if not users or #users == 0 then return true end

    local user = users[1]
    local token = generate_token()
    local expiry = current_timestamp() + RESET_TOKEN_EXPIRY
    local token_hash = crypto.to_hex(crypto.sha256(token))

    db.run("UPDATE _users SET reset_token = ?, reset_token_expiry = ? WHERE id = ?", { token_hash, expiry, user.id })

    if mail.is_enabled() and app_url then
        local ok, err = mail.send_password_reset(user.email, token, app_url)
        if not ok then log.error("mail", "failed to send password reset email", { error = err }) end
    end

    log.info("auth", "password reset requested", { user_id = user.id })
    return true
end

function auth.confirm_password_reset(token, new_password)
    if not token then return nil, "token required" end
    if not new_password or #new_password < MIN_PASSWORD_LENGTH then
        return nil, "password must be at least " .. MIN_PASSWORD_LENGTH .. " characters"
    end

    local token_hash = crypto.to_hex(crypto.sha256(token))
    local now = current_timestamp()

    local users =
        db.query("SELECT id FROM _users WHERE reset_token = ? AND reset_token_expiry > ?", { token_hash, now })

    if not users or #users == 0 then return nil, "invalid or expired token" end

    local user = users[1]
    local salt = generate_salt()
    local password_hash = hash_password(new_password, salt)

    db.run(
        "UPDATE _users SET password_hash = ?, password_salt = ?, reset_token = NULL, reset_token_expiry = NULL WHERE id = ?",
        { password_hash, salt, user.id }
    )

    log.info("auth", "password reset completed", { user_id = user.id })
    return true
end

-- email verification --

function auth.request_verification(user_id, app_url)
    if not user_id then return nil, "user_id required" end

    local users = db.query("SELECT id, email, verified FROM _users WHERE id = ?", { user_id })
    if not users or #users == 0 then return nil, "user not found" end

    local user = users[1]
    if user.verified == 1 then return nil, "already verified" end

    local token = generate_token()
    local expiry = current_timestamp() + VERIFY_TOKEN_EXPIRY
    local token_hash = crypto.to_hex(crypto.sha256(token))

    db.run("UPDATE _users SET verify_token = ?, verify_token_expiry = ? WHERE id = ?", { token_hash, expiry, user.id })

    if mail.is_enabled() and app_url then
        local ok, err = mail.send_verification(user.email, token, app_url)
        if not ok then log.error("mail", "failed to send verification email", { error = err }) end
    end

    log.info("auth", "verification requested", { user_id = user.id })
    return true
end

function auth.confirm_verification(token)
    if not token then return nil, "token required" end

    local token_hash = crypto.to_hex(crypto.sha256(token))
    local now = current_timestamp()

    local users =
        db.query("SELECT id FROM _users WHERE verify_token = ? AND verify_token_expiry > ?", { token_hash, now })

    if not users or #users == 0 then return nil, "invalid or expired token" end

    local user = users[1]

    db.run("UPDATE _users SET verified = 1, verify_token = NULL, verify_token_expiry = NULL WHERE id = ?", { user.id })

    log.info("auth", "email verified", { user_id = user.id })
    return true
end

-- oauth --

function auth.find_or_create_oauth_user(email, provider, _provider_id)
    if not email then return nil, "email required" end

    local users = db.query("SELECT id, email FROM _users WHERE email = ?", { email })

    if users and #users > 0 then
        log.info("auth", "oauth login", { user_id = users[1].id, provider = provider })
        return users[1]
    end

    local random_password = crypto.to_hex(crypto.random_bytes(32))
    local salt = generate_salt()
    local password_hash = hash_password(random_password, salt)

    local id, err = db.insert(
        "INSERT INTO _users (email, password_hash, password_salt, verified) VALUES (?, ?, ?, 1)",
        { email, password_hash, salt }
    )
    if not id then return nil, err end

    log.info("auth", "oauth user created", { user_id = id, email = email, provider = provider })

    return { id = id, email = email }
end

return auth
