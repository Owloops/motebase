local socket = require("socket")
local poll = require("motebase.poll")
local router = require("motebase.router")
local middleware = require("motebase.middleware")
local log = require("motebase.utils.log")
local http_parser = require("motebase.parser.http")
local ratelimit = require("motebase.ratelimit")

local server = {}

-- IANA HTTP Status Codes (http://www.iana.org/assignments/http-status-codes)
local status_text = setmetatable({
    -- 1xx Informational
    [100] = "Continue",
    [101] = "Switching Protocols",
    [102] = "Processing",
    [103] = "Early Hints",
    -- 2xx Success
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [203] = "Non-Authoritative Information",
    [204] = "No Content",
    [205] = "Reset Content",
    [206] = "Partial Content",
    [207] = "Multi-Status",
    [208] = "Already Reported",
    [226] = "IM Used",
    -- 3xx Redirection
    [300] = "Multiple Choices",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [305] = "Use Proxy",
    [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    -- 4xx Client Errors
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [402] = "Payment Required",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [406] = "Not Acceptable",
    [407] = "Proxy Authentication Required",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length Required",
    [412] = "Precondition Failed",
    [413] = "Content Too Large",
    [414] = "URI Too Long",
    [415] = "Unsupported Media Type",
    [416] = "Range Not Satisfiable",
    [417] = "Expectation Failed",
    [418] = "I'm a teapot",
    [421] = "Misdirected Request",
    [422] = "Unprocessable Content",
    [423] = "Locked",
    [424] = "Failed Dependency",
    [425] = "Too Early",
    [426] = "Upgrade Required",
    [428] = "Precondition Required",
    [429] = "Too Many Requests",
    [431] = "Request Header Fields Too Large",
    [451] = "Unavailable For Legal Reasons",
    -- 5xx Server Errors
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
    [505] = "HTTP Version Not Supported",
    [506] = "Variant Also Negotiates",
    [507] = "Insufficient Storage",
    [508] = "Loop Detected",
    [510] = "Not Extended",
    [511] = "Network Authentication Required",
}, {
    __index = function()
        return "Unknown"
    end,
})

local DEFAULT_KEEP_ALIVE_TIMEOUT = 5
local DEFAULT_KEEP_ALIVE_MAX = 100
local DEFAULT_MAX_CONCURRENT = 10000

-- socket --

local function create_client_wrapper(client)
    client:settimeout(0)
    local ip, _ = client:getpeername()
    return {
        socket = client,
        read_buffer = "",
        write_buffer = "",
        last_activity = socket.gettime(),
        request_count = 0,
        keep_alive = true,
        ip = ip or "unknown",
    }
end

local function receive_line(wrapper)
    while true do
        local nl = wrapper.read_buffer:find("\r?\n")
        if nl then
            local line = wrapper.read_buffer:sub(1, nl - 1):gsub("\r$", "")
            wrapper.read_buffer = wrapper.read_buffer:sub(nl + 1):gsub("^\n", "")
            return line
        end

        local chunk, err, partial = wrapper.socket:receive(4096)
        if chunk then
            wrapper.read_buffer = wrapper.read_buffer .. chunk
            wrapper.last_activity = socket.gettime()
        elseif partial and #partial > 0 then
            wrapper.read_buffer = wrapper.read_buffer .. partial
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantread" then
            coroutine.yield("read")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end
end

local function receive_bytes(wrapper, count)
    while #wrapper.read_buffer < count do
        local chunk, err, partial = wrapper.socket:receive(4096)
        if chunk then
            wrapper.read_buffer = wrapper.read_buffer .. chunk
            wrapper.last_activity = socket.gettime()
        elseif partial and #partial > 0 then
            wrapper.read_buffer = wrapper.read_buffer .. partial
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantread" then
            coroutine.yield("read")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end

    local data = wrapper.read_buffer:sub(1, count)
    wrapper.read_buffer = wrapper.read_buffer:sub(count + 1)
    return data
end

local function send_all(wrapper, data)
    wrapper.write_buffer = wrapper.write_buffer .. data
    while #wrapper.write_buffer > 0 do
        local sent, err, last_sent = wrapper.socket:send(wrapper.write_buffer)
        if sent then
            wrapper.write_buffer = wrapper.write_buffer:sub(sent + 1)
            wrapper.last_activity = socket.gettime()
        elseif last_sent and last_sent > 0 then
            wrapper.write_buffer = wrapper.write_buffer:sub(last_sent + 1)
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantwrite" then
            coroutine.yield("write")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end
    return true
end

-- http --

local function parse_request_line(line)
    return http_parser.parse_request_line(line)
end

local function parse_headers(wrapper)
    local header_lines = {}
    while true do
        local line, err = receive_line(wrapper)
        if err then return nil, err end
        if not line or line == "" then break end
        header_lines[#header_lines + 1] = line
    end
    return http_parser.parse_headers(table.concat(header_lines, "\n"))
end

local function read_body(wrapper, headers)
    local content_length = headers["content-length"]
    if not content_length or content_length == 0 then return nil end
    return receive_bytes(wrapper, content_length)
end

local function send_response(wrapper, status, headers, body, keep_alive)
    local response = "HTTP/1.1 " .. status .. " " .. (status_text[status] or "OK") .. "\r\n"

    headers = headers or {}
    if body then headers["Content-Length"] = #body end

    if keep_alive then
        headers["Connection"] = "keep-alive"
        headers["Keep-Alive"] = "timeout=" .. DEFAULT_KEEP_ALIVE_TIMEOUT .. ", max=" .. DEFAULT_KEEP_ALIVE_MAX
    else
        headers["Connection"] = "close"
    end

    for name, value in pairs(headers) do
        response = response .. name .. ": " .. value .. "\r\n"
    end

    response = response .. "\r\n"
    if body then response = response .. body end

    return send_all(wrapper, response)
end

local function send_sse_headers(wrapper, status, headers)
    headers["Connection"] = "keep-alive"
    local response = "HTTP/1.1 " .. status .. " " .. (status_text[status] or "OK") .. "\r\n"
    for name, value in pairs(headers) do
        response = response .. name .. ": " .. value .. "\r\n"
    end
    response = response .. "\r\n"
    return send_all(wrapper, response)
end

-- request --

local function create_context(method, path, headers, body, config)
    return {
        method = method,
        path = path,
        headers = headers,
        body = body,
        config = config,
        user = nil,
        params = {},
        _status = nil,
        _response_headers = {},
        _response_body = nil,
    }
end

local function should_keep_alive(http_version, headers, wrapper, config)
    if wrapper.request_count >= (config.keep_alive_max or DEFAULT_KEEP_ALIVE_MAX) then return false end

    local connection = headers["connection"]
    if connection then
        connection = connection:lower()
        if connection == "close" then return false end
        if connection == "keep-alive" then return true end
    end

    return tonumber(http_version) >= 1.1
end

local function handle_request(wrapper, config)
    wrapper.request_count = wrapper.request_count + 1

    local line, err = receive_line(wrapper)
    if err then return false, false, err end

    -- RFC 7230 Section 3.5: ignore at least one empty line before request-line
    if line == "" then
        line, err = receive_line(wrapper)
        if err then return false, false, err end
    end

    local req = parse_request_line(line)
    if not req then
        send_response(wrapper, 400, {}, "Bad Request", false)
        return false, false, "bad request"
    end

    local headers, headers_err = parse_headers(wrapper)
    if headers_err then return false, false, headers_err end

    local keep_alive = should_keep_alive(req.version, headers, wrapper, config)

    local body_raw, body_err = read_body(wrapper, headers)
    if body_err then return false, false, body_err end

    local path = req.location.path or "/"
    local query = req.location.query

    if middleware.is_preflight(req.method) then
        local cors = middleware.cors_headers()
        cors["Content-Length"] = "0"
        send_response(wrapper, 204, cors, nil, keep_alive)
        log.info("http", req.method .. " " .. path .. " 204")
        return true, keep_alive, nil
    end

    if config.ratelimit ~= false and not ratelimit.check(wrapper.ip, path) then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        cors["Retry-After"] = "60"
        send_response(wrapper, 429, cors, middleware.encode_json({ error = "too many requests" }), keep_alive)
        log.info("http", req.method .. " " .. path .. " 429")
        return true, keep_alive, nil
    end

    local body, parse_err, is_multipart = middleware.parse_body(body_raw, headers)
    if parse_err then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 400, cors, middleware.encode_json({ error = parse_err }), keep_alive)
        return true, keep_alive, nil
    end

    local ctx = create_context(req.method, path, headers, body, config)
    ctx.query_string = query
    ctx.full_path = path .. (query and ("?" .. query) or "")
    ctx.is_multipart = is_multipart

    local auth_payload, auth_err = middleware.extract_auth(headers, config.secret)
    if auth_payload then
        ctx.user = auth_payload
    elseif auth_err then
        ctx.auth_error = auth_err
    end

    local handler, params = router.match(req.method, path)
    if not handler then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 404, cors, middleware.encode_json({ error = "not found" }), keep_alive)
        log.info("http", req.method .. " " .. path .. " 404")
        return true, keep_alive, nil
    end

    ctx.params = params or {}

    local ok, handler_err = pcall(handler, ctx)
    if not ok then
        io.stderr:write("handler error: " .. tostring(handler_err) .. "\n")
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 500, cors, middleware.encode_json({ error = "internal server error" }), false)
        return true, false, nil
    end

    local resp_headers = middleware.cors_headers()
    for k, v in pairs(ctx._response_headers) do
        resp_headers[k] = v
    end
    local status = ctx._status or 200

    if ctx._sse_mode and ctx._sse_client then
        send_sse_headers(wrapper, status, resp_headers)
        log.info("http", req.method .. " " .. path .. " " .. status .. " (SSE)")
        return true, false, nil, ctx._sse_client
    end

    send_response(wrapper, status, resp_headers, ctx._response_body, keep_alive)
    log.info("http", req.method .. " " .. path .. " " .. status)
    return true, keep_alive, nil
end

local function handle_client(wrapper, config)
    while true do
        local ok, keep_alive, err, sse_client = handle_request(wrapper, config)

        if not ok then return false, err end
        if sse_client then return true, nil, sse_client end
        if not keep_alive then return true, nil end

        wrapper.keep_alive = true
    end
end

local function resume_coroutine(c)
    local ok, result = coroutine.resume(c.coro)
    if not ok then
        io.stderr:write("coroutine error: " .. tostring(result) .. "\n")
        c.wrapper.socket:close()
        c.waiting = nil
        return false
    elseif coroutine.status(c.coro) ~= "dead" then
        c.waiting = result
        return true
    else
        c.wrapper.socket:close()
        c.waiting = nil
        return false
    end
end

-- server --

function server.create(config)
    config = config or {}
    config.host = config.host or "0.0.0.0"
    config.port = config.port or 8080
    config.secret = config.secret or os.getenv("MOTEBASE_SECRET") or "change-me-in-production"
    config.timeout = config.timeout or 30
    config.keep_alive_timeout = config.keep_alive_timeout or DEFAULT_KEEP_ALIVE_TIMEOUT
    config.keep_alive_max = config.keep_alive_max or DEFAULT_KEEP_ALIVE_MAX
    config.max_concurrent = config.max_concurrent or DEFAULT_MAX_CONCURRENT

    local srv, err = socket.bind(config.host, config.port)
    if not srv then return nil, "failed to bind: " .. (err or "unknown error") end

    srv:settimeout(0)

    local clients = {}
    local sse_mod = require("motebase.realtime.sse")

    local instance = {
        _socket = srv,
        _config = config,
        _running = false,
        _clients = clients,
    }

    local function handle_new_connection(client_sock)
        if #clients >= config.max_concurrent then
            client_sock:close()
            log.warn("http", "max concurrent connections reached, rejecting client")
            return
        end

        local wrapper = create_client_wrapper(client_sock)
        local coro = coroutine.create(function()
            return handle_client(wrapper, config)
        end)

        local ok, result, _, sse_client = coroutine.resume(coro)
        if not ok then
            io.stderr:write("coroutine error: " .. tostring(result) .. "\n")
            client_sock:close()
            return
        end

        if coroutine.status(coro) ~= "dead" then
            table.insert(clients, { wrapper = wrapper, coro = coro, waiting = result })
            return
        end

        if sse_client then
            local sse_coro = sse_mod.create_handler(wrapper, sse_client, send_all)
            local sse_ok, sse_result = coroutine.resume(sse_coro)
            if not sse_ok then
                io.stderr:write("SSE error: " .. tostring(sse_result) .. "\n")
                sse_mod.cleanup(sse_client)
                client_sock:close()
                return
            end
            if coroutine.status(sse_coro) ~= "dead" then
                table.insert(clients, {
                    wrapper = wrapper,
                    coro = sse_coro,
                    waiting = sse_result,
                    sse_client = sse_client,
                })
                return
            end
        end

        client_sock:close()
    end

    local function process_readable(readable)
        local socket_to_client = {}
        for _, c in ipairs(clients) do
            if c.waiting == "read" then socket_to_client[c.wrapper.socket] = c end
        end

        for _, sock in ipairs(readable) do
            if sock == instance._socket then
                local client_sock = instance._socket:accept()
                if client_sock then handle_new_connection(client_sock) end
            else
                local c = socket_to_client[sock]
                if c then resume_coroutine(c) end
            end
        end
    end

    local function process_writable(writable)
        local socket_to_client = {}
        for _, c in ipairs(clients) do
            if c.waiting == "write" then socket_to_client[c.wrapper.socket] = c end
        end

        for _, sock in ipairs(writable) do
            local c = socket_to_client[sock]
            if c then resume_coroutine(c) end
        end
    end

    local function process_sse_clients()
        for _, c in ipairs(clients) do
            if sse_mod.should_resume(c) then
                if not resume_coroutine(c) and c.sse_client then
                    sse_mod.cleanup(c.sse_client)
                else
                    c.wrapper.last_activity = socket.gettime()
                end
            end
        end
    end

    local function cleanup_timed_out()
        local now = socket.gettime()
        local new_clients = {}

        for _, c in ipairs(clients) do
            if not c.waiting then goto continue end

            local timeout
            if c.sse_client then
                timeout = sse_mod.IDLE_TIMEOUT
            elseif c.wrapper.request_count > 0 then
                timeout = config.keep_alive_timeout
            else
                timeout = config.timeout
            end

            if now - c.wrapper.last_activity > timeout then
                c.wrapper.socket:close()
                if c.sse_client then sse_mod.cleanup(c.sse_client) end
            else
                table.insert(new_clients, c)
            end

            ::continue::
        end

        return new_clients
    end

    function instance:run()
        self._running = true
        print(string.format("Server listening on %s:%d (async)", config.host, config.port))

        while self._running do
            local read_sockets = { self._socket }
            local write_sockets = {}

            for _, c in ipairs(clients) do
                if c.waiting == "read" then
                    table.insert(read_sockets, c.wrapper.socket)
                elseif c.waiting == "write" then
                    table.insert(write_sockets, c.wrapper.socket)
                end
            end

            local readable, writable = poll.select(read_sockets, write_sockets, 0.1)

            if readable then process_readable(readable) end
            if writable then process_writable(writable) end

            process_sse_clients()

            clients = cleanup_timed_out()
            self._clients = clients
        end
    end

    function instance:stop()
        self._running = false
        for _, c in ipairs(self._clients) do
            pcall(function()
                c.wrapper.socket:close()
            end)
        end
        self._socket:close()
    end

    function instance:active_connections()
        return #self._clients
    end

    function instance:config()
        return self._config
    end

    return instance
end

-- response --

function server.json(ctx, status, data)
    ctx._status = status
    ctx._response_headers["Content-Type"] = "application/json"
    ctx._response_body = middleware.encode_json(data)
end

function server.error(ctx, status, message)
    server.json(ctx, status, { error = message })
end

function server.file(ctx, status, data, filename, mime_type)
    ctx._status = status
    ctx._response_headers["Content-Type"] = mime_type or "application/octet-stream"
    ctx._response_headers["Content-Disposition"] = 'inline; filename="' .. (filename or "download") .. '"'
    ctx._response_body = data
end

function server.download(ctx, status, data, filename, mime_type)
    ctx._status = status
    ctx._response_headers["Content-Type"] = mime_type or "application/octet-stream"
    ctx._response_headers["Content-Disposition"] = 'attachment; filename="' .. (filename or "download") .. '"'
    ctx._response_body = data
end

function server.sse(ctx, client)
    ctx._sse_mode = true
    ctx._sse_client = client
    ctx._status = 200
    ctx._response_headers["Content-Type"] = "text/event-stream"
    ctx._response_headers["Cache-Control"] = "no-store"
    ctx._response_headers["X-Accel-Buffering"] = "no"
end

function server.redirect(ctx, url)
    ctx._status = 302
    ctx._response_headers["Location"] = url
    ctx._response_body = ""
end

server._should_keep_alive = should_keep_alive
server._DEFAULT_KEEP_ALIVE_MAX = DEFAULT_KEEP_ALIVE_MAX

return server
