local socket = require("socket")
local jobs = require("motebase.jobs")
local log = require("motebase.utils.log")

local worker = {}

local running = false

function worker.run(options)
    options = options or {}

    local min_interval = options.min_interval or 0.1
    local max_interval = options.max_interval or 5
    local poll_interval = min_interval

    running = true

    log.info("worker", "started", {
        min_interval = min_interval,
        max_interval = max_interval,
    })

    while running do
        local job = jobs.claim_next()

        if job then
            log.info("worker", "processing job", {
                id = job.id,
                name = job.name,
                attempt = job.attempts,
            })

            local ok, err = pcall(jobs.process, job)
            if not ok then
                log.error("worker", "job processing error", {
                    id = job.id,
                    name = job.name,
                    error = tostring(err),
                })
            end

            poll_interval = min_interval
        else
            socket.sleep(poll_interval)
            poll_interval = math.min(poll_interval * 2, max_interval)
        end
    end

    log.info("worker", "stopped")
end

function worker.stop()
    running = false
end

function worker.is_running()
    return running
end

return worker
