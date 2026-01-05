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
        elseif a == "--help" then
            return nil, "help"
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
    print("  -p, --port <port>       Port to listen on (default: 8080)")
    print("  -h, --host <host>       Host to bind to (default: 0.0.0.0)")
    print("  -d, --db <path>         Database file path (default: motebase.db)")
    print("  -s, --secret <key>      JWT secret key")
    print("  --storage <path>        File storage directory (default: ./storage)")
    print("  --max-file-size <bytes> Max upload size in bytes (default: 10485760)")
    print("  --help                  Show this help message")
    print("")
    print("Environment variables:")
    print("  MOTEBASE_SECRET         JWT secret key")
    print("  MOTEBASE_DB             Database file path")
    print("  MOTEBASE_STORAGE        File storage directory")
    print("  MOTEBASE_MAX_FILE_SIZE  Max upload size in bytes")
    print("  MOTEBASE_LOG            Enable logging (0 to disable)")
end

local function main()
    local config, action = parse_args(arg)

    if action == "help" then
        print_help()
        os.exit(0)
    end

    local motebase = require("motebase")
    local output = require("motebase.utils.output")

    local srv, err = motebase.start(config)
    if not srv then
        io.stderr:write(output.color("red") .. "✗" .. output.reset() .. " failed to start: " .. tostring(err) .. "\n")
        os.exit(1)
    end

    local cfg = srv:config()
    io.stderr:write(
        output.color("green")
            .. "✓"
            .. output.reset()
            .. " motebase running on http://"
            .. cfg.host
            .. ":"
            .. cfg.port
            .. "\n"
    )
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

    srv:run()
end

main()
