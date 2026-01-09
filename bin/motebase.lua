#!/usr/bin/env lua

package.path = package.path .. ";?.lua;?/init.lua"

local function parse_args(args)
    local config = {}
    local i = 1
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

local function print_help()
    print("Usage: motebase [options]")
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
    print("  MOTEBASE_MAX_FILE_SIZE  Max upload size in bytes")
    print("  MOTEBASE_SUPERUSER      Superuser email")
    print("  MOTEBASE_RATELIMIT      Requests per minute (0 to disable)")
    print("  MOTEBASE_MAX_CONNECTIONS  Max concurrent connections")
    print("  MOTEBASE_LOG            Enable logging (0 to disable)")
end

local function main()
    local config, err = parse_args(arg)

    if err == "help" then
        print_help()
        os.exit(0)
    end

    if not config then
        io.stderr:write("error: " .. err .. "\n")
        io.stderr:write("run 'motebase --help' for usage\n")
        os.exit(1)
    end

    local motebase = require("motebase")
    local output = require("motebase.utils.output")
    local log = require("motebase.utils.log")

    local srv, start_err = motebase.start(config)
    if not srv then
        io.stderr:write(
            output.color("red") .. "✗" .. output.reset() .. " failed to start: " .. tostring(start_err) .. "\n"
        )
        os.exit(1)
    end

    local cfg = srv:config()
    local base_url = "http://" .. cfg.host .. ":" .. cfg.port
    io.stderr:write(output.color("green") .. "✓" .. output.reset() .. " motebase running\n")
    io.stderr:write(output.color("blue") .. "→" .. output.reset() .. " api: " .. base_url .. "/api/\n")
    io.stderr:write(output.color("blue") .. "→" .. output.reset() .. " admin: " .. base_url .. "/_/\n")
    io.stderr:write(output.color("blue") .. "→" .. output.reset() .. " database: " .. cfg.db_path .. "\n")
    io.stderr:write(output.color("blue") .. "→" .. output.reset() .. " storage: " .. cfg.storage_path .. "\n")
    io.stderr:write(output.color("bright_black") .. "→" .. output.reset() .. " press Ctrl+C to stop\n")

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
            io.stderr:write("\n" .. output.color("bright_black") .. "→" .. output.reset() .. " stopped\n")
        else
            io.stderr:write(output.color("red") .. "✗" .. output.reset() .. " " .. tostring(run_err) .. "\n")
            os.exit(1)
        end
    end
end

main()
