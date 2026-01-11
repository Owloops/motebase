#!/usr/bin/env lua

package.path = package.path .. ";?.lua;?/init.lua"

local function parse_serve_args(args, start_idx)
    local config = {}
    local i = start_idx
    while i <= #args do
        local a = args[i]
        if a == "--port" or a == "-p" then
            config.port = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--host" or a == "-h" then
            config.host = args[i + 1]
            i = i + 2
        elseif a == "--db" or a == "-d" then
            config.db_path = args[i + 1]
            i = i + 2
        elseif a == "--secret" or a == "-s" then
            config.secret = args[i + 1]
            i = i + 2
        elseif a == "--storage" then
            config.storage_path = args[i + 1]
            i = i + 2
        elseif a == "--max-file-size" then
            config.max_file_size = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--superuser" then
            config.superuser = args[i + 1]
            i = i + 2
        elseif a == "--ratelimit" then
            config.ratelimit = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--max-connections" then
            config.max_concurrent = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--hooks" or a == "-H" then
            config.hooks = args[i + 1]
            i = i + 2
        elseif a == "--help" then
            return nil, "help"
        elseif a:sub(1, 1) == "-" then
            return nil, "unknown option: " .. a
        else
            i = i + 1
        end
    end
    return config
end

local function parse_worker_args(args, start_idx)
    local config = {}
    local i = start_idx
    while i <= #args do
        local a = args[i]
        if a == "--db" or a == "-d" then
            config.db_path = args[i + 1]
            i = i + 2
        elseif a == "--min-interval" then
            config.min_interval = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--max-interval" then
            config.max_interval = tonumber(args[i + 1])
            i = i + 2
        elseif a == "--hooks" or a == "-H" then
            config.hooks = args[i + 1]
            i = i + 2
        elseif a == "--help" then
            return nil, "help"
        elseif a:sub(1, 1) == "-" then
            return nil, "unknown option: " .. a
        else
            i = i + 1
        end
    end
    return config
end

local function parse_jobs_args(args, start_idx)
    local config = { subcommand = nil, args = {} }
    local i = start_idx

    if i <= #args and args[i]:sub(1, 1) ~= "-" then
        config.subcommand = args[i]
        i = i + 1
    end

    while i <= #args do
        local a = args[i]
        if a == "--db" or a == "-d" then
            config.db_path = args[i + 1]
            i = i + 2
        elseif a == "--status" then
            config.status = args[i + 1]
            i = i + 2
        elseif a == "--all-failed" then
            config.all_failed = true
            i = i + 1
        elseif a == "--completed" then
            config.completed = true
            i = i + 1
        elseif a == "--failed" then
            config.failed = true
            i = i + 1
        elseif a == "--help" then
            return nil, "help"
        elseif a:sub(1, 1) == "-" then
            return nil, "unknown option: " .. a
        else
            config.args[#config.args + 1] = a
            i = i + 1
        end
    end
    return config
end

local function print_main_help()
    print("Usage: motebase <command> [options]")
    print("")
    print("Commands:")
    print("  serve       Start the HTTP server (default)")
    print("  worker      Start the background job worker")
    print("  jobs        Manage background jobs")
    print("  cron        Manage cron jobs")
    print("")
    print("Run 'motebase <command> --help' for command-specific options.")
end

local function print_serve_help()
    print("Usage: motebase serve [options]")
    print("")
    print("Start the HTTP server.")
    print("")
    print("Options:")
    print("  -p, --port <port>       Port to listen on (default: 8097)")
    print("  -h, --host <host>       Host to bind to (default: 0.0.0.0)")
    print("  -d, --db <path>         Database file path (default: motebase.db)")
    print("  -s, --secret <key>      JWT secret key")
    print("  --storage <path>        File storage directory (default: ./storage)")
    print("  --max-file-size <bytes> Max upload size in bytes (default: 10485760)")
    print("  --superuser <email>     Superuser email (bypasses API rules)")
    print("  --ratelimit <n>         Requests per minute (0 to disable, default: 100)")
    print("  --max-connections <n>   Max concurrent connections (default: 10000)")
    print("  -H, --hooks <path>      Lua file to load for custom hooks/routes")
    print("  --help                  Show this help message")
    print("")
    print("Environment variables:")
    print("  MOTEBASE_SECRET         JWT secret key")
    print("  MOTEBASE_DB             Database file path")
    print("  MOTEBASE_STORAGE        File storage directory")
    print("  MOTEBASE_SUPERUSER      Superuser email")
    print("  MOTEBASE_RATELIMIT      Requests per minute (0 to disable)")
    print("  MOTEBASE_MAX_CONNECTIONS  Max concurrent connections")
end

local function print_worker_help()
    print("Usage: motebase worker [options]")
    print("")
    print("Start the background job worker.")
    print("")
    print("Options:")
    print("  -d, --db <path>         Database file path (default: motebase.db)")
    print("  --min-interval <sec>    Min poll interval in seconds (default: 0.1)")
    print("  --max-interval <sec>    Max poll interval in seconds (default: 5)")
    print("  -H, --hooks <path>      Lua file to load for job handlers")
    print("  --help                  Show this help message")
    print("")
    print("The worker polls the database for pending jobs and executes them.")
    print("Job handlers must be registered in the hooks file using motebase.on_job().")
end

local function print_jobs_help()
    print("Usage: motebase jobs <subcommand> [options]")
    print("")
    print("Manage background jobs.")
    print("")
    print("Subcommands:")
    print("  list                    List jobs")
    print("  stats                   Show job queue statistics")
    print("  retry <id>              Retry a failed job")
    print("  retry --all-failed      Retry all failed jobs")
    print("  delete <id>             Delete a job")
    print("  clear --completed       Clear completed jobs")
    print("  clear --failed          Clear failed jobs")
    print("")
    print("Options:")
    print("  -d, --db <path>         Database file path (default: motebase.db)")
    print("  --status <status>       Filter by status (pending, running, completed, failed)")
    print("  --help                  Show this help message")
end

local function print_cron_help()
    print("Usage: motebase cron <subcommand>")
    print("")
    print("Manage cron jobs.")
    print("")
    print("Subcommands:")
    print("  list                    List registered cron jobs")
    print("")
    print("Options:")
    print("  -H, --hooks <path>      Lua file to load for cron job definitions")
    print("  --help                  Show this help message")
    print("")
    print("Note: Cron jobs are registered in hooks.lua and run in the HTTP server process.")
end

local function parse_cron_args(args, start_idx)
    local config = { subcommand = nil }
    local i = start_idx

    if i <= #args and args[i]:sub(1, 1) ~= "-" then
        config.subcommand = args[i]
        i = i + 1
    end

    while i <= #args do
        local a = args[i]
        if a == "--hooks" or a == "-H" then
            config.hooks = args[i + 1]
            i = i + 2
        elseif a == "--help" then
            return nil, "help"
        elseif a:sub(1, 1) == "-" then
            return nil, "unknown option: " .. a
        else
            i = i + 1
        end
    end
    return config
end

local function cmd_serve(config)
    local motebase = require("motebase")
    local output = require("motebase.utils.output")
    local log = require("motebase.utils.log")

    local srv, start_err = motebase.start(config)
    if not srv then
        io.stderr:write(
            output.color("red") .. "x" .. output.reset() .. " failed to start: " .. tostring(start_err) .. "\n"
        )
        os.exit(1)
    end

    local cfg = srv:config()
    local base_url = "http://" .. cfg.host .. ":" .. cfg.port
    io.stderr:write(output.color("green") .. "+" .. output.reset() .. " motebase running\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " api: " .. base_url .. "/api/\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " admin: " .. base_url .. "/_/\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " database: " .. cfg.db_path .. "\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " storage: " .. cfg.storage_path .. "\n")
    io.stderr:write(output.color("bright_black") .. "->" .. output.reset() .. " press Ctrl+C to stop\n")

    if cfg.secret == "change-me-in-production" then
        io.stderr:write(
            output.color("yellow")
                .. "!"
                .. output.reset()
                .. " using default JWT secret - set MOTEBASE_SECRET in production\n"
        )
    end

    if config.hooks then
        local hooks_path = config.hooks
        local ok, hooks_err = pcall(dofile, hooks_path)
        if not ok then
            log.error("hooks", "failed to load hooks file", { path = hooks_path, error = tostring(hooks_err) })
            os.exit(1)
        end
        log.info("hooks", "loaded hooks file", { path = hooks_path })
    end

    local ok, run_err = pcall(function()
        srv:run()
    end)
    if not ok then
        if run_err and run_err:find("interrupted") then
            io.stderr:write("\n" .. output.color("bright_black") .. "->" .. output.reset() .. " stopped\n")
        else
            io.stderr:write(output.color("red") .. "x" .. output.reset() .. " " .. tostring(run_err) .. "\n")
            os.exit(1)
        end
    end
end

local function cmd_worker(config)
    local db = require("motebase.db")
    local migrations = require("motebase.migrations")
    local worker = require("motebase.jobs.worker")
    local output = require("motebase.utils.output")
    local log = require("motebase.utils.log")

    local db_path = config.db_path or os.getenv("MOTEBASE_DB") or "./motebase.db"

    local ok, err = db.open(db_path)
    if not ok then
        io.stderr:write(
            output.color("red") .. "x" .. output.reset() .. " failed to open database: " .. tostring(err) .. "\n"
        )
        os.exit(1)
    end

    local migrate_ok, migrate_err = migrations.run()
    if not migrate_ok then
        io.stderr:write(
            output.color("red") .. "x" .. output.reset() .. " migration failed: " .. tostring(migrate_err) .. "\n"
        )
        os.exit(1)
    end

    if config.hooks then
        local hooks_path = config.hooks
        local hooks_ok, hooks_err = pcall(dofile, hooks_path)
        if not hooks_ok then
            log.error("hooks", "failed to load hooks file", { path = hooks_path, error = tostring(hooks_err) })
            os.exit(1)
        end
        log.info("hooks", "loaded hooks file", { path = hooks_path })
    end

    local jobs = require("motebase.jobs")
    local handlers = jobs.list_handlers()

    io.stderr:write(output.color("green") .. "+" .. output.reset() .. " worker started\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " database: " .. db_path .. "\n")
    io.stderr:write(output.color("blue") .. "->" .. output.reset() .. " handlers: " .. #handlers .. " registered\n")
    if #handlers > 0 then
        io.stderr:write(output.color("bright_black") .. "   " .. table.concat(handlers, ", ") .. output.reset() .. "\n")
    end
    io.stderr:write(output.color("bright_black") .. "->" .. output.reset() .. " press Ctrl+C to stop\n")

    local run_ok, run_err = pcall(function()
        worker.run({
            min_interval = config.min_interval,
            max_interval = config.max_interval,
        })
    end)

    if not run_ok then
        if run_err and run_err:find("interrupted") then
            io.stderr:write("\n" .. output.color("bright_black") .. "->" .. output.reset() .. " stopped\n")
        else
            io.stderr:write(output.color("red") .. "x" .. output.reset() .. " " .. tostring(run_err) .. "\n")
            os.exit(1)
        end
    end

    db.close()
end

local function cmd_cron(config)
    local cron = require("motebase.cron")
    local output = require("motebase.utils.output")
    local log = require("motebase.utils.log")

    cron.register_builtin_jobs()

    if config.hooks then
        local hooks_path = config.hooks
        local ok, hooks_err = pcall(dofile, hooks_path)
        if not ok then
            log.error("hooks", "failed to load hooks file", { path = hooks_path, error = tostring(hooks_err) })
            io.stderr:write(
                output.color("red") .. "x" .. output.reset() .. " failed to load hooks: " .. tostring(hooks_err) .. "\n"
            )
            os.exit(1)
        end
    end

    local subcommand = config.subcommand

    if not subcommand or subcommand == "list" then
        local list = cron.list()
        print(string.format("Cron Jobs (%d total):", #list))
        print("")
        if #list == 0 then
            print("  No cron jobs registered.")
        else
            print(string.format("  %-25s  %-16s  %s", "ID", "SCHEDULE", "NEXT RUN"))
            print(
                string.format(
                    "  %-25s  %-16s  %s",
                    "-------------------------",
                    "----------------",
                    "-------------------"
                )
            )
            for _, job in ipairs(list) do
                local id = job.id
                if #id > 25 then id = id:sub(1, 22) .. "..." end
                local next_run = job.next_run and os.date("%Y-%m-%d %H:%M:%S", job.next_run) or "N/A"
                print(string.format("  %-25s  %-16s  %s", id, job.expression, next_run))
            end
        end
    else
        io.stderr:write("Error: unknown subcommand: " .. subcommand .. "\n")
        io.stderr:write("Run 'motebase cron --help' for usage.\n")
        os.exit(1)
    end
end

local function cmd_jobs(config)
    local db = require("motebase.db")
    local migrations = require("motebase.migrations")
    local jobs = require("motebase.jobs")
    local output = require("motebase.utils.output")

    local db_path = config.db_path or os.getenv("MOTEBASE_DB") or "./motebase.db"

    local ok, err = db.open(db_path)
    if not ok then
        io.stderr:write(
            output.color("red") .. "x" .. output.reset() .. " failed to open database: " .. tostring(err) .. "\n"
        )
        os.exit(1)
    end

    local migrate_ok, migrate_err = migrations.run()
    if not migrate_ok then
        io.stderr:write(
            output.color("red") .. "x" .. output.reset() .. " migration failed: " .. tostring(migrate_err) .. "\n"
        )
        os.exit(1)
    end

    local subcommand = config.subcommand

    if not subcommand or subcommand == "list" then
        local result = jobs.list({ status = config.status })
        print(string.format("Jobs (%d total):", result.totalItems))
        print("")
        if #result.items == 0 then
            print("  No jobs found.")
        else
            print(string.format("  %-6s  %-10s  %-20s  %-8s  %s", "ID", "STATUS", "NAME", "ATTEMPTS", "CREATED"))
            print(
                string.format(
                    "  %-6s  %-10s  %-20s  %-8s  %s",
                    "------",
                    "----------",
                    "--------------------",
                    "--------",
                    "-------------------"
                )
            )
            for _, job in ipairs(result.items) do
                local created = os.date("%Y-%m-%d %H:%M:%S", job.created_at)
                local name = job.name
                if #name > 20 then name = name:sub(1, 17) .. "..." end
                print(
                    string.format(
                        "  %-6d  %-10s  %-20s  %d/%-5d  %s",
                        job.id,
                        job.status,
                        name,
                        job.attempts,
                        job.max_attempts,
                        created
                    )
                )
            end
        end
    elseif subcommand == "stats" then
        local stats = jobs.stats()
        print("Job Queue Statistics:")
        print("")
        print(string.format("  Pending:    %d", stats.pending))
        print(string.format("  Running:    %d", stats.running))
        print(string.format("  Completed:  %d", stats.completed))
        print(string.format("  Failed:     %d", stats.failed))
        print(string.format("  %-10s  --", ""))
        print(string.format("  Total:      %d", stats.total))
    elseif subcommand == "retry" then
        if config.all_failed then
            local count = jobs.retry_all_failed()
            print(string.format("Retried %d failed job(s).", count))
        elseif #config.args > 0 then
            local job_id = tonumber(config.args[1])
            if not job_id then
                io.stderr:write("Error: invalid job ID\n")
                os.exit(1)
            end
            local retry_ok, retry_err = jobs.retry(job_id)
            if retry_ok then
                print(string.format("Job %d queued for retry.", job_id))
            else
                io.stderr:write("Error: " .. (retry_err or "unknown error") .. "\n")
                os.exit(1)
            end
        else
            io.stderr:write("Error: specify job ID or --all-failed\n")
            os.exit(1)
        end
    elseif subcommand == "delete" then
        if #config.args == 0 then
            io.stderr:write("Error: specify job ID\n")
            os.exit(1)
        end
        local job_id = tonumber(config.args[1])
        if not job_id then
            io.stderr:write("Error: invalid job ID\n")
            os.exit(1)
        end
        local delete_ok = jobs.delete(job_id)
        if delete_ok then
            print(string.format("Job %d deleted.", job_id))
        else
            io.stderr:write("Error: job not found\n")
            os.exit(1)
        end
    elseif subcommand == "clear" then
        local status = nil
        if config.completed then
            status = "completed"
        elseif config.failed then
            status = "failed"
        end

        if not status then
            io.stderr:write("Error: specify --completed or --failed\n")
            os.exit(1)
        end

        local count = jobs.clear(status)
        print(string.format("Cleared %d %s job(s).", count, status))
    else
        io.stderr:write("Error: unknown subcommand: " .. subcommand .. "\n")
        io.stderr:write("Run 'motebase jobs --help' for usage.\n")
        os.exit(1)
    end

    db.close()
end

local function main()
    local command = arg[1]

    if not command or command == "--help" or command == "-h" then
        print_main_help()
        os.exit(0)
    end

    if command == "serve" then
        local config, err = parse_serve_args(arg, 2)
        if err == "help" then
            print_serve_help()
            os.exit(0)
        end
        if not config then
            io.stderr:write("error: " .. err .. "\n")
            os.exit(1)
        end
        cmd_serve(config)
    elseif command == "worker" then
        local config, err = parse_worker_args(arg, 2)
        if err == "help" then
            print_worker_help()
            os.exit(0)
        end
        if not config then
            io.stderr:write("error: " .. err .. "\n")
            os.exit(1)
        end
        cmd_worker(config)
    elseif command == "jobs" then
        local config, err = parse_jobs_args(arg, 2)
        if err == "help" then
            print_jobs_help()
            os.exit(0)
        end
        if not config then
            io.stderr:write("error: " .. err .. "\n")
            os.exit(1)
        end
        cmd_jobs(config)
    elseif command == "cron" then
        local config, err = parse_cron_args(arg, 2)
        if err == "help" then
            print_cron_help()
            os.exit(0)
        end
        if not config then
            io.stderr:write("error: " .. err .. "\n")
            os.exit(1)
        end
        cmd_cron(config)
    elseif command:sub(1, 1) == "-" then
        local config, err = parse_serve_args(arg, 1)
        if err == "help" then
            print_serve_help()
            os.exit(0)
        end
        if not config then
            io.stderr:write("error: " .. err .. "\n")
            os.exit(1)
        end
        cmd_serve(config)
    else
        io.stderr:write("error: unknown command: " .. command .. "\n")
        io.stderr:write("run 'motebase --help' for usage\n")
        os.exit(1)
    end
end

main()
