local sqlite3 = require("lsqlite3complete")

local db = {}

local conn

local function bind_params(stmt, params)
    if not params then return end
    for i, v in ipairs(params) do
        if type(v) == "boolean" then
            stmt:bind(i, v and 1 or 0)
        else
            stmt:bind(i, v)
        end
    end
end

function db.open(path)
    path = path or ":memory:"
    local err
    conn, err = sqlite3.open(path)
    if not conn then return nil, "failed to open database: " .. (err or "unknown error") end
    conn:busy_timeout(5000)
    conn:exec("PRAGMA foreign_keys = ON")
    conn:exec("PRAGMA journal_mode = WAL")
    conn:exec("PRAGMA synchronous = NORMAL")
    return true
end

function db.close()
    if conn then
        conn:close()
        conn = nil
    end
end

function db.exec(sql)
    if not conn then return nil, "database not open" end
    local result = conn:exec(sql)
    if result ~= sqlite3.OK then return nil, conn:errmsg() end
    return true
end

function db.query(sql, params)
    if not conn then return nil, "database not open" end
    local stmt = conn:prepare(sql)
    if not stmt then return nil, conn:errmsg() end

    bind_params(stmt, params)

    local rows = {}
    for row in stmt:nrows() do
        rows[#rows + 1] = row
    end
    stmt:finalize()
    return rows
end

function db.insert(sql, params)
    if not conn then return nil, "database not open" end
    local stmt = conn:prepare(sql)
    if not stmt then return nil, conn:errmsg() end

    bind_params(stmt, params)

    local result = stmt:step()
    stmt:finalize()

    if result ~= sqlite3.DONE then return nil, conn:errmsg() end
    return conn:last_insert_rowid()
end

function db.run(sql, params)
    if not conn then return nil, "database not open" end
    local stmt = conn:prepare(sql)
    if not stmt then return nil, conn:errmsg() end

    bind_params(stmt, params)

    local result = stmt:step()
    stmt:finalize()

    if result ~= sqlite3.DONE then return nil, conn:errmsg() end
    return conn:changes()
end

function db.get_connection()
    return conn
end

return db
