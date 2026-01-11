local db = require("motebase.db")

local migrations = {}

local SCHEMA_VERSION_KEY = "_schema_version"

-- migrations --

local registry = {
    [1] = {
        name = "initial_schema",
        up = function()
            db.exec([[
                CREATE TABLE IF NOT EXISTS _settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ]])

            db.exec([[
                CREATE TABLE IF NOT EXISTS _collections (
                    id TEXT PRIMARY KEY,
                    name TEXT UNIQUE NOT NULL,
                    schema TEXT NOT NULL,
                    type TEXT DEFAULT 'base',
                    listRule TEXT,
                    viewRule TEXT,
                    createRule TEXT,
                    updateRule TEXT,
                    deleteRule TEXT,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ]])

            db.exec([[
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

            db.exec([[
                CREATE TABLE IF NOT EXISTS _logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    method TEXT NOT NULL,
                    path TEXT NOT NULL,
                    status INTEGER NOT NULL,
                    duration_ms INTEGER,
                    ip TEXT,
                    user_id INTEGER,
                    user_agent TEXT,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ]])

            db.exec("CREATE INDEX IF NOT EXISTS idx_logs_created_at ON _logs(created_at DESC)")
            db.exec("CREATE INDEX IF NOT EXISTS idx_logs_status ON _logs(status)")
            db.exec("CREATE INDEX IF NOT EXISTS idx_logs_path ON _logs(path)")
        end,
    },

    [2] = {
        name = "add_jobs_table",
        up = function()
            db.exec([[
                CREATE TABLE IF NOT EXISTS _jobs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    payload TEXT,
                    status TEXT DEFAULT 'pending',
                    priority TEXT DEFAULT 'normal',
                    attempts INTEGER DEFAULT 0,
                    max_attempts INTEGER DEFAULT 1,
                    timeout INTEGER DEFAULT 1800,
                    result TEXT,
                    error TEXT,
                    run_at INTEGER,
                    started_at INTEGER,
                    completed_at INTEGER,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            ]])

            db.exec([[
                CREATE INDEX IF NOT EXISTS idx_jobs_status_priority_run_at
                ON _jobs(status, priority, run_at, created_at)
            ]])
        end,
    },
}

-- helpers --

local function get_version()
    local rows = db.query("SELECT value FROM _settings WHERE key = ?", { SCHEMA_VERSION_KEY })
    if not rows or #rows == 0 then return 0 end
    return tonumber(rows[1].value) or 0
end

local function set_version(version)
    local existing = db.query("SELECT key FROM _settings WHERE key = ?", { SCHEMA_VERSION_KEY })
    if existing and #existing > 0 then
        db.run(
            "UPDATE _settings SET value = ?, updated_at = strftime('%s', 'now') WHERE key = ?",
            { tostring(version), SCHEMA_VERSION_KEY }
        )
    else
        db.insert("INSERT INTO _settings (key, value) VALUES (?, ?)", { SCHEMA_VERSION_KEY, tostring(version) })
    end
end

local function ensure_settings_table()
    db.exec([[
        CREATE TABLE IF NOT EXISTS _settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    ]])
end

-- public --

function migrations.run()
    ensure_settings_table()

    local current = get_version()
    local target = #registry

    if current >= target then return true end

    for version = current + 1, target do
        local m = registry[version]
        if not m then return nil, "missing migration: " .. version end

        local ok, err = db.transaction(function()
            m.up()
            set_version(version)
        end)

        if not ok then return nil, "migration " .. version .. " failed: " .. (err or "unknown") end
    end

    return true
end

function migrations.current_version()
    ensure_settings_table()
    return get_version()
end

function migrations.target_version()
    return #registry
end

return migrations
