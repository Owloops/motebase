local log = require("motebase.utils.log")

local cron = {}

local jobs = {}
local running = false
local last_tick = 0

-- macros --

local MACROS = {
    ["@yearly"] = "0 0 1 1 *",
    ["@annually"] = "0 0 1 1 *",
    ["@monthly"] = "0 0 1 * *",
    ["@weekly"] = "0 0 * * 0",
    ["@daily"] = "0 0 * * *",
    ["@midnight"] = "0 0 * * *",
    ["@hourly"] = "0 * * * *",
}

-- parsing --

local function parse_field(field, min, max)
    local values = {}

    for part in field:gmatch("[^,]+") do
        part = part:match("^%s*(.-)%s*$")

        if part == "*" then
            for i = min, max do
                values[i] = true
            end
        elseif part:match("^%*/(%d+)$") then
            local step = tonumber(part:match("^%*/(%d+)$"))
            if step and step > 0 then
                for i = min, max, step do
                    values[i] = true
                end
            end
        elseif part:match("^(%d+)%-(%d+)$") then
            local start_val, end_val = part:match("^(%d+)%-(%d+)$")
            start_val, end_val = tonumber(start_val), tonumber(end_val)
            if start_val and end_val and start_val >= min and end_val <= max then
                for i = start_val, end_val do
                    values[i] = true
                end
            end
        elseif part:match("^(%d+)%-(%d+)/(%d+)$") then
            local start_val, end_val, step = part:match("^(%d+)%-(%d+)/(%d+)$")
            start_val, end_val, step = tonumber(start_val), tonumber(end_val), tonumber(step)
            if start_val and end_val and step and step > 0 and start_val >= min and end_val <= max then
                for i = start_val, end_val, step do
                    values[i] = true
                end
            end
        elseif part:match("^%d+$") then
            local val = tonumber(part)
            if val and val >= min and val <= max then values[val] = true end
        end
    end

    return values
end

local function parse_expression(expr)
    if MACROS[expr] then expr = MACROS[expr] end

    local parts = {}
    for part in expr:gmatch("%S+") do
        parts[#parts + 1] = part
    end

    if #parts ~= 5 then return nil, "invalid cron expression: expected 5 fields" end

    local schedule = {
        minutes = parse_field(parts[1], 0, 59),
        hours = parse_field(parts[2], 0, 23),
        days = parse_field(parts[3], 1, 31),
        months = parse_field(parts[4], 1, 12),
        weekdays = parse_field(parts[5], 0, 6),
    }

    if
        not next(schedule.minutes)
        or not next(schedule.hours)
        or not next(schedule.days)
        or not next(schedule.months)
        or not next(schedule.weekdays)
    then
        return nil, "invalid cron expression: invalid field values"
    end

    return schedule
end

local function is_due(schedule, timestamp)
    local t = os.date("*t", timestamp)

    if not schedule.minutes[t.min] then return false end
    if not schedule.hours[t.hour] then return false end
    if not schedule.months[t.month] then return false end

    local day_match = schedule.days[t.day]
    local weekday_match = schedule.weekdays[t.wday - 1]

    local days_is_star = true
    for i = 1, 31 do
        if not schedule.days[i] then
            days_is_star = false
            break
        end
    end

    local weekdays_is_star = true
    for i = 0, 6 do
        if not schedule.weekdays[i] then
            weekdays_is_star = false
            break
        end
    end

    if days_is_star and weekdays_is_star then
        return true
    elseif days_is_star then
        return weekday_match
    elseif weekdays_is_star then
        return day_match
    else
        return day_match or weekday_match
    end
end

local function next_run(schedule, from_time)
    local t = os.date("*t", from_time)
    t.sec = 0
    t.min = t.min + 1

    for _ = 1, 366 * 24 * 60 do
        if t.min > 59 then
            t.min = 0
            t.hour = t.hour + 1
        end
        if t.hour > 23 then
            t.hour = 0
            t.day = t.day + 1
        end

        local ts = os.time(t)
        if not ts then break end

        t = os.date("*t", ts)

        if is_due(schedule, ts) then return ts end

        t.min = t.min + 1
    end

    return nil
end

-- public api --

function cron.add(id, expression, handler)
    if type(id) ~= "string" or #id == 0 then return nil, "job id must be a non-empty string" end
    if type(handler) ~= "function" then return nil, "handler must be a function" end

    local schedule, err = parse_expression(expression)
    if not schedule then return nil, err end

    jobs[id] = {
        id = id,
        expression = expression,
        schedule = schedule,
        handler = handler,
        next_run = next_run(schedule, os.time()),
        last_run = nil,
    }

    return true
end

function cron.remove(id)
    jobs[id] = nil
end

function cron.list()
    local result = {}
    for id, job in pairs(jobs) do
        result[#result + 1] = {
            id = id,
            expression = job.expression,
            next_run = job.next_run,
            last_run = job.last_run,
        }
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end

function cron.get(id)
    local job = jobs[id]
    if not job then return nil end
    return {
        id = job.id,
        expression = job.expression,
        next_run = job.next_run,
        last_run = job.last_run,
    }
end

-- tick function called by server loop --

function cron.tick()
    local now = os.time()

    local current_minute = math.floor(now / 60)
    if current_minute == last_tick then return end
    last_tick = current_minute

    for id, job in pairs(jobs) do
        if is_due(job.schedule, now) then
            local ok, err = pcall(job.handler)
            job.last_run = now
            job.next_run = next_run(job.schedule, now)

            if not ok then
                log.error("cron", "job failed", { id = id, error = tostring(err) })
            else
                log.debug("cron", "job completed", { id = id })
            end
        end
    end
end

function cron.start()
    running = true
end

function cron.stop()
    running = false
end

function cron.is_running()
    return running
end

function cron.clear()
    jobs = {}
end

-- built-in jobs --

function cron.register_builtin_jobs()
    local db = require("motebase.db")

    cron.add("__mb_logs_cleanup__", "0 */6 * * *", function()
        local cutoff = os.time() - (7 * 24 * 60 * 60)
        local changes = db.run("DELETE FROM _logs WHERE created_at < ?", { cutoff })
        if changes and changes > 0 then log.info("cron", "cleaned up old logs", { deleted = changes }) end
    end)

    cron.add("__mb_db_optimize__", "0 3 * * *", function()
        db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        db.exec("PRAGMA optimize")
        log.info("cron", "database optimized")
    end)

    cron.add("__mb_jobs_cleanup__", "0 4 * * *", function()
        local cutoff = os.time() - (7 * 24 * 60 * 60)
        local changes = db.run("DELETE FROM _jobs WHERE status = 'completed' AND completed_at < ?", { cutoff })
        if changes and changes > 0 then log.info("cron", "cleaned up old jobs", { deleted = changes }) end
    end)

    cron.add("__mb_jobs_timeout__", "*/5 * * * *", function()
        local jobs_mod = require("motebase.jobs")
        jobs_mod.timeout_stale()
    end)
end

return cron
