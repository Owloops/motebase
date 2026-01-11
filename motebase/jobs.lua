local db = require("motebase.db")
local cjson = require("cjson")
local log = require("motebase.utils.log")

local jobs = {}

-- handler registry --

local handlers = {}

function jobs.register(name, handler)
    if type(name) ~= "string" or #name == 0 then return nil, "job name must be a non-empty string" end
    if type(handler) ~= "function" then return nil, "handler must be a function" end
    handlers[name] = handler
    return true
end

function jobs.unregister(name)
    handlers[name] = nil
end

function jobs.get_handler(name)
    return handlers[name]
end

function jobs.list_handlers()
    local list = {}
    for name in pairs(handlers) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

-- queue operations --

local PRIORITY_ORDER = { high = 1, normal = 2, low = 3 }
local DEFAULT_TIMEOUT = 1800 -- 30 minutes

local function now()
    return os.time()
end

function jobs.queue(name, payload, options)
    options = options or {}

    if type(name) ~= "string" or #name == 0 then return nil, "job name must be a non-empty string" end

    local priority = options.priority or "normal"
    if not PRIORITY_ORDER[priority] then return nil, "invalid priority: must be high, normal, or low" end

    local max_attempts = options.attempts or 1
    if max_attempts < 1 then max_attempts = 1 end

    local timeout = options.timeout or DEFAULT_TIMEOUT

    local run_at = nil
    if options.delay and options.delay > 0 then run_at = now() + options.delay end

    local payload_json = nil
    if payload ~= nil then
        local ok, encoded = pcall(cjson.encode, payload)
        if not ok then return nil, "failed to encode payload: " .. tostring(encoded) end
        payload_json = encoded
    end

    local current_time = now()
    local job_id, err = db.insert(
        [[
            INSERT INTO _jobs (name, payload, status, priority, max_attempts, timeout, run_at, created_at, updated_at)
            VALUES (?, ?, 'pending', ?, ?, ?, ?, ?, ?)
        ]],
        {
            name,
            payload_json or cjson.null,
            priority,
            max_attempts,
            timeout,
            run_at or cjson.null,
            current_time,
            current_time,
        }
    )

    if not job_id then return nil, "failed to queue job: " .. (err or "unknown error") end

    return job_id
end

-- job retrieval --

local function row_to_job(row)
    if not row then return nil end

    local job = {
        id = row.id,
        name = row.name,
        status = row.status,
        priority = row.priority,
        attempts = row.attempts,
        max_attempts = row.max_attempts,
        timeout = row.timeout,
        error = row.error,
        run_at = row.run_at,
        started_at = row.started_at,
        completed_at = row.completed_at,
        created_at = row.created_at,
        updated_at = row.updated_at,
    }

    if row.payload then
        local ok, decoded = pcall(cjson.decode, row.payload)
        job.payload = ok and decoded or row.payload
    end

    if row.result then
        local ok, decoded = pcall(cjson.decode, row.result)
        job.result = ok and decoded or row.result
    end

    return job
end

function jobs.get(id)
    local rows = db.query("SELECT * FROM _jobs WHERE id = ?", { id })
    if not rows or #rows == 0 then return nil end
    return row_to_job(rows[1])
end

function jobs.list(options)
    options = options or {}

    local page = options.page or 1
    local per_page = options.per_page or 50
    local offset = (page - 1) * per_page

    local where_clauses = {}
    local params = {}

    if options.status then
        where_clauses[#where_clauses + 1] = "status = ?"
        params[#params + 1] = options.status
    end

    if options.name then
        where_clauses[#where_clauses + 1] = "name = ?"
        params[#params + 1] = options.name
    end

    local where_sql = ""
    if #where_clauses > 0 then where_sql = "WHERE " .. table.concat(where_clauses, " AND ") end

    local count_rows = db.query("SELECT COUNT(*) as total FROM _jobs " .. where_sql, params)
    local total_items = count_rows and count_rows[1] and count_rows[1].total or 0

    local list_params = {}
    for _, p in ipairs(params) do
        list_params[#list_params + 1] = p
    end
    list_params[#list_params + 1] = per_page
    list_params[#list_params + 1] = offset

    local rows =
        db.query("SELECT * FROM _jobs " .. where_sql .. " ORDER BY created_at DESC LIMIT ? OFFSET ?", list_params)

    local items = {}
    if rows then
        for _, row in ipairs(rows) do
            items[#items + 1] = row_to_job(row)
        end
    end

    return {
        page = page,
        perPage = per_page,
        totalItems = total_items,
        totalPages = math.ceil(total_items / per_page),
        items = items,
    }
end

function jobs.stats()
    local rows = db.query([[
        SELECT
            status,
            COUNT(*) as count
        FROM _jobs
        GROUP BY status
    ]])

    local stats = {
        pending = 0,
        running = 0,
        completed = 0,
        failed = 0,
        total = 0,
    }

    if rows then
        for _, row in ipairs(rows) do
            stats[row.status] = row.count
            stats.total = stats.total + row.count
        end
    end

    return stats
end

-- worker operations --

function jobs.claim_next()
    local current_time = now()

    local ok, err = db.transaction(function()
        local rows = db.query(
            [[
                SELECT id FROM _jobs
                WHERE status = 'pending'
                  AND (run_at IS NULL OR run_at <= ?)
                ORDER BY
                    CASE priority
                        WHEN 'high' THEN 1
                        WHEN 'normal' THEN 2
                        WHEN 'low' THEN 3
                    END,
                    created_at
                LIMIT 1
            ]],
            { current_time }
        )

        if not rows or #rows == 0 then return nil end

        local job_id = rows[1].id
        db.run(
            [[
                UPDATE _jobs
                SET status = 'running',
                    started_at = ?,
                    attempts = attempts + 1,
                    updated_at = ?
                WHERE id = ?
            ]],
            { current_time, current_time, job_id }
        )
    end)

    if not ok then
        log.error("jobs", "failed to claim job", { error = err })
        return nil
    end

    local rows = db.query(
        "SELECT * FROM _jobs WHERE status = 'running' AND started_at = ? ORDER BY id DESC LIMIT 1",
        { current_time }
    )

    if not rows or #rows == 0 then return nil end
    return row_to_job(rows[1])
end

function jobs.mark_completed(job_id, result)
    local result_json = nil
    if result ~= nil then
        local ok, encoded = pcall(cjson.encode, result)
        if ok then result_json = encoded end
    end

    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'completed',
                result = ?,
                completed_at = ?,
                updated_at = ?
            WHERE id = ?
        ]],
        { result_json or cjson.null, now(), now(), job_id }
    )

    return changes and changes > 0
end

function jobs.mark_failed(job_id, error_msg)
    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'failed',
                error = ?,
                completed_at = ?,
                updated_at = ?
            WHERE id = ?
        ]],
        { tostring(error_msg), now(), now(), job_id }
    )

    return changes and changes > 0
end

function jobs.mark_pending(job_id, delay)
    delay = delay or 0
    local run_at = delay > 0 and (now() + delay) or cjson.null

    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'pending',
                run_at = ?,
                updated_at = ?
            WHERE id = ?
        ]],
        { run_at, now(), job_id }
    )

    return changes and changes > 0
end

-- job management --

function jobs.retry(job_id)
    local job = jobs.get(job_id)
    if not job then return nil, "job not found" end
    if job.status ~= "failed" then return nil, "can only retry failed jobs" end

    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'pending',
                attempts = 0,
                error = NULL,
                result = NULL,
                run_at = NULL,
                started_at = NULL,
                completed_at = NULL,
                updated_at = ?
            WHERE id = ?
        ]],
        { now(), job_id }
    )

    return changes and changes > 0
end

function jobs.retry_all_failed()
    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'pending',
                attempts = 0,
                error = NULL,
                result = NULL,
                run_at = NULL,
                started_at = NULL,
                completed_at = NULL,
                updated_at = ?
            WHERE status = 'failed'
        ]],
        { now() }
    )

    return changes or 0
end

function jobs.delete(job_id)
    local changes = db.run("DELETE FROM _jobs WHERE id = ?", { job_id })
    return changes and changes > 0
end

function jobs.clear(status)
    if status then
        local changes = db.run("DELETE FROM _jobs WHERE status = ?", { status })
        return changes or 0
    else
        local changes = db.run("DELETE FROM _jobs WHERE status IN ('completed', 'failed')")
        return changes or 0
    end
end

function jobs.clear_all()
    local changes = db.run("DELETE FROM _jobs")
    return changes or 0
end

function jobs.clear_handlers()
    handlers = {}
end

function jobs.timeout_stale()
    local current_time = now()
    local changes = db.run(
        [[
            UPDATE _jobs
            SET status = 'failed',
                error = 'job timed out',
                completed_at = ?,
                updated_at = ?
            WHERE status = 'running'
              AND started_at IS NOT NULL
              AND (started_at + COALESCE(timeout, 1800)) < ?
        ]],
        { current_time, current_time, current_time }
    )

    if changes and changes > 0 then log.warn("jobs", "timed out stale jobs", { count = changes }) end

    return changes or 0
end

-- process a single job --

function jobs.process(job)
    local handler = handlers[job.name]

    if not handler then
        jobs.mark_failed(job.id, "no handler registered for: " .. job.name)
        log.warn("jobs", "no handler for job", { id = job.id, name = job.name })
        return false, "no handler"
    end

    local ok, result = pcall(handler, job.payload)

    if ok then
        jobs.mark_completed(job.id, result)
        log.info("jobs", "job completed", { id = job.id, name = job.name })
        return true
    else
        local error_msg = tostring(result)

        if job.attempts >= job.max_attempts then
            jobs.mark_failed(job.id, error_msg)
            log.error("jobs", "job failed (max attempts)", {
                id = job.id,
                name = job.name,
                attempts = job.attempts,
                error = error_msg,
            })
            return false, "max attempts reached"
        else
            local delay = job.attempts * job.attempts
            jobs.mark_pending(job.id, delay)
            log.warn("jobs", "job failed (will retry)", {
                id = job.id,
                name = job.name,
                attempts = job.attempts,
                max_attempts = job.max_attempts,
                retry_delay = delay,
                error = error_msg,
            })
            return false, "will retry"
        end
    end
end

-- built-in job handlers --

function jobs.register_builtin_handlers()
    local mail = require("motebase.mail")

    jobs.register("__mb_send_password_reset__", function(payload)
        local ok, err = mail.send_password_reset(payload.email, payload.token, payload.app_url)
        if not ok then error("failed to send password reset email: " .. (err or "unknown error")) end
        return { sent = true, email = payload.email }
    end)

    jobs.register("__mb_send_verification__", function(payload)
        local ok, err = mail.send_verification(payload.email, payload.token, payload.app_url)
        if not ok then error("failed to send verification email: " .. (err or "unknown error")) end
        return { sent = true, email = payload.email }
    end)
end

return jobs
