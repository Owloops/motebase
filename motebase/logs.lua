local db = require("motebase.db")
local socket = require("socket")

local logs = {}

local config = {
    enabled = true,
    max_logs = 10000,
    retention_days = 7,
}

function logs.init()
    local ok, err = db.exec([[
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
    if not ok then return nil, err end

    db.exec("CREATE INDEX IF NOT EXISTS idx_logs_created_at ON _logs(created_at DESC)")
    db.exec("CREATE INDEX IF NOT EXISTS idx_logs_status ON _logs(status)")
    db.exec("CREATE INDEX IF NOT EXISTS idx_logs_path ON _logs(path)")

    return true
end

function logs.configure(opts)
    if opts.enabled ~= nil then config.enabled = opts.enabled end
    if opts.max_logs then config.max_logs = opts.max_logs end
    if opts.retention_days then config.retention_days = opts.retention_days end
end

function logs.is_enabled()
    return config.enabled
end

function logs.record(entry)
    if not config.enabled then return true end

    if entry.path:match("^/_/") and entry.path ~= "/_/" then return true end

    local _, err = db.insert(
        [[
        INSERT INTO _logs (method, path, status, duration_ms, ip, user_id, user_agent)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]],
        {
            entry.method,
            entry.path,
            entry.status,
            entry.duration_ms,
            entry.ip,
            entry.user_id,
            entry.user_agent,
        }
    )

    if err then return nil, err end

    if math.random() < 0.01 then logs.cleanup() end

    return true
end

function logs.list(opts)
    opts = opts or {}
    local page = opts.page or 1
    local per_page = math.min(opts.per_page or 50, 200)
    local offset = (page - 1) * per_page

    local where_clauses = {}
    local params = {}

    if opts.status then
        if opts.status == "error" then
            where_clauses[#where_clauses + 1] = "status >= 400"
        elseif opts.status == "success" then
            where_clauses[#where_clauses + 1] = "status < 400"
        elseif tonumber(opts.status) then
            where_clauses[#where_clauses + 1] = "status = ?"
            params[#params + 1] = tonumber(opts.status)
        end
    end

    if opts.method then
        where_clauses[#where_clauses + 1] = "method = ?"
        params[#params + 1] = opts.method:upper()
    end

    if opts.path then
        where_clauses[#where_clauses + 1] = "path LIKE ?"
        params[#params + 1] = "%" .. opts.path .. "%"
    end

    if opts.user_id then
        where_clauses[#where_clauses + 1] = "user_id = ?"
        params[#params + 1] = tonumber(opts.user_id)
    end

    if opts.from then
        where_clauses[#where_clauses + 1] = "created_at >= ?"
        params[#params + 1] = tonumber(opts.from)
    end
    if opts.to then
        where_clauses[#where_clauses + 1] = "created_at <= ?"
        params[#params + 1] = tonumber(opts.to)
    end

    local where_sql = ""
    if #where_clauses > 0 then where_sql = " WHERE " .. table.concat(where_clauses, " AND ") end

    local count_sql = "SELECT COUNT(*) as count FROM _logs" .. where_sql
    local count_result = db.query(count_sql, params)
    local total = count_result and count_result[1] and count_result[1].count or 0

    local query_params = {}
    for _, p in ipairs(params) do
        query_params[#query_params + 1] = p
    end
    query_params[#query_params + 1] = per_page
    query_params[#query_params + 1] = offset

    local sql = "SELECT * FROM _logs" .. where_sql .. " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    local rows = db.query(sql, query_params)

    return {
        page = page,
        perPage = per_page,
        totalItems = total,
        totalPages = math.ceil(total / per_page),
        items = rows or {},
    }
end

function logs.get_stats()
    local day_ago = os.time() - (24 * 60 * 60)

    local stats = {
        total_requests = 0,
        success_count = 0,
        error_count = 0,
        avg_duration_ms = 0,
        requests_by_method = {},
        requests_by_status = {},
    }

    local total_result = db.query(
        [[
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN status < 400 THEN 1 ELSE 0 END) as success,
            SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END) as errors,
            AVG(duration_ms) as avg_duration
        FROM _logs WHERE created_at >= ?
    ]],
        { day_ago }
    )

    if total_result and total_result[1] then
        stats.total_requests = total_result[1].total or 0
        stats.success_count = total_result[1].success or 0
        stats.error_count = total_result[1].errors or 0
        stats.avg_duration_ms = math.floor(total_result[1].avg_duration or 0)
    end

    local method_result = db.query(
        [[
        SELECT method, COUNT(*) as count
        FROM _logs WHERE created_at >= ?
        GROUP BY method ORDER BY count DESC
    ]],
        { day_ago }
    )

    if method_result then
        for _, row in ipairs(method_result) do
            stats.requests_by_method[row.method] = row.count
        end
    end

    local status_result = db.query(
        [[
        SELECT
            CASE
                WHEN status >= 500 THEN '5xx'
                WHEN status >= 400 THEN '4xx'
                WHEN status >= 300 THEN '3xx'
                WHEN status >= 200 THEN '2xx'
                ELSE 'other'
            END as status_group,
            COUNT(*) as count
        FROM _logs WHERE created_at >= ?
        GROUP BY status_group ORDER BY status_group
    ]],
        { day_ago }
    )

    if status_result then
        for _, row in ipairs(status_result) do
            stats.requests_by_status[row.status_group] = row.count
        end
    end

    return stats
end

function logs.cleanup()
    local cutoff = os.time() - (config.retention_days * 24 * 60 * 60)
    db.run("DELETE FROM _logs WHERE created_at < ?", { cutoff })

    local count_result = db.query("SELECT COUNT(*) as count FROM _logs")
    if count_result and count_result[1] and count_result[1].count > config.max_logs then
        local excess = count_result[1].count - config.max_logs
        db.run(
            [[
            DELETE FROM _logs WHERE id IN (
                SELECT id FROM _logs ORDER BY created_at ASC LIMIT ?
            )
        ]],
            { excess }
        )
    end
end

function logs.clear()
    return db.run("DELETE FROM _logs")
end

function logs.start_timer()
    return socket.gettime()
end

function logs.get_duration_ms(start_time)
    return math.floor((socket.gettime() - start_time) * 1000)
end

return logs
