local db = require("motebase.db")
local jwt = require("motebase.jwt")
local crypto = require("motebase.crypto")
local log = require("motebase.utils.log")
local email_parser = require("motebase.parser.email")

local auth = {}

local superuser_email = nil

-- helpers --

local function generate_salt()
    return crypto.to_hex(crypto.random_bytes(16))
end

local function hash_password(password, salt)
    return crypto.to_hex(crypto.sha256(salt .. password))
end

function auth.init()
    return db.exec([[
        CREATE TABLE IF NOT EXISTS _users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT NOT NULL,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
end

function auth.register(email, password)
    if not email or not password then return nil, "email and password required" end

    if not email_parser.is_valid(email) then return nil, "invalid email format" end

    if #password < 8 then return nil, "password must be at least 8 characters" end

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
    if opts and opts.superuser then superuser_email = opts.superuser end
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

return auth
