local socket = require("socket")
local router = require("motebase.router")
local middleware = require("motebase.middleware")
local log = require("motebase.utils.log")
local http_parser = require("motebase.parser.http")

local server = {}

local status_text = {
    [200] = "OK",
    [201] = "Created",
    [204] = "No Content",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [404] = "Not Found",
    [500] = "Internal Server Error",
}

-- socket --

local function create_client_wrapper(client)
    client:settimeout(0)
    return {
        socket = client,
        read_buffer = "",
        write_buffer = "",
        last_activity = socket.gettime(),
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

local function send_response(wrapper, status, headers, body)
    local response = "HTTP/1.1 " .. status .. " " .. (status_text[status] or "OK") .. "\r\n"

    headers = headers or {}
    if body then headers["Content-Length"] = #body end
    headers["Connection"] = "close"

    for name, value in pairs(headers) do
        response = response .. name .. ": " .. value .. "\r\n"
    end

    response = response .. "\r\n"
    if body then response = response .. body end

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

local function handle_client(wrapper, config)
    local line, err = receive_line(wrapper)
    if err then return false, err end

    local req = parse_request_line(line)
    if not req then
        send_response(wrapper, 400, {}, "Bad Request")
        return false, "bad request"
    end

    local headers, headers_err = parse_headers(wrapper)
    if headers_err then return false, headers_err end

    local body_raw, body_err = read_body(wrapper, headers)
    if body_err then return false, body_err end

    local path = req.location.path or "/"
    local query = req.location.query

    if middleware.is_preflight(req.method) then
        local cors = middleware.cors_headers()
        cors["Content-Length"] = "0"
        send_response(wrapper, 204, cors, nil)
        log.info("http", req.method .. " " .. path .. " 204")
        return true
    end

    local body, parse_err, is_multipart = middleware.parse_body(body_raw, headers)
    if parse_err then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 400, cors, middleware.encode_json({ error = parse_err }))
        return true
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
        send_response(wrapper, 404, cors, middleware.encode_json({ error = "not found" }))
        log.info("http", req.method .. " " .. path .. " 404")
        return true
    end

    ctx.params = params or {}

    local ok, handler_err = pcall(handler, ctx)
    if not ok then
        io.stderr:write("handler error: " .. tostring(handler_err) .. "\n")
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 500, cors, middleware.encode_json({ error = "internal server error" }))
        return true
    end

    local resp_headers = middleware.cors_headers()
    for k, v in pairs(ctx._response_headers) do
        resp_headers[k] = v
    end
    local status = ctx._status or 200
    send_response(wrapper, status, resp_headers, ctx._response_body)
    log.info("http", req.method .. " " .. path .. " " .. status)
    return true
end

-- server --

function server.create(config)
    config = config or {}
    config.host = config.host or "0.0.0.0"
    config.port = config.port or 8080
    config.secret = config.secret or os.getenv("MOTEBASE_SECRET") or "change-me-in-production"
    config.timeout = config.timeout or 30

    local srv, err = socket.bind(config.host, config.port)
    if not srv then return nil, "failed to bind: " .. (err or "unknown error") end

    srv:settimeout(0)

    local clients = {}

    local instance = {
        _socket = srv,
        _config = config,
        _running = false,
        _clients = clients,
    }

    function instance:run()
        self._running = true
        print(string.format("Server listening on %s:%d (async)", config.host, config.port))

        while self._running do
            local read_sockets = { self._socket }
            local write_sockets = {}
            local socket_to_client = {}

            for _, c in ipairs(clients) do
                if c.waiting == "read" then
                    table.insert(read_sockets, c.wrapper.socket)
                    socket_to_client[c.wrapper.socket] = c
                elseif c.waiting == "write" then
                    table.insert(write_sockets, c.wrapper.socket)
                    socket_to_client[c.wrapper.socket] = c
                end
            end

            local readable, writable = socket.select(read_sockets, write_sockets, 0.1)

            if readable then
                for _, sock in ipairs(readable) do
                    if sock == self._socket then
                        local client_sock = self._socket:accept()
                        if client_sock then
                            local wrapper = create_client_wrapper(client_sock)
                            local coro = coroutine.create(function()
                                return handle_client(wrapper, self._config)
                            end)
                            local ok, result = coroutine.resume(coro)
                            if not ok then
                                io.stderr:write("coroutine error: " .. tostring(result) .. "\n")
                                client_sock:close()
                            elseif coroutine.status(coro) ~= "dead" then
                                table.insert(clients, { wrapper = wrapper, coro = coro, waiting = result })
                            else
                                client_sock:close()
                            end
                        end
                    else
                        local c = socket_to_client[sock]
                        if c then
                            local ok, result = coroutine.resume(c.coro)
                            if not ok then
                                io.stderr:write("coroutine error: " .. tostring(result) .. "\n")
                                c.wrapper.socket:close()
                                c.waiting = nil
                            elseif coroutine.status(c.coro) ~= "dead" then
                                c.waiting = result
                            else
                                c.wrapper.socket:close()
                                c.waiting = nil
                            end
                        end
                    end
                end
            end

            if writable then
                for _, sock in ipairs(writable) do
                    local c = socket_to_client[sock]
                    if c then
                        local ok, result = coroutine.resume(c.coro)
                        if not ok then
                            io.stderr:write("coroutine error: " .. tostring(result) .. "\n")
                            c.wrapper.socket:close()
                            c.waiting = nil
                        elseif coroutine.status(c.coro) ~= "dead" then
                            c.waiting = result
                        else
                            c.wrapper.socket:close()
                            c.waiting = nil
                        end
                    end
                end
            end

            local now = socket.gettime()
            local new_clients = {}
            for _, c in ipairs(clients) do
                if c.waiting then
                    if now - c.wrapper.last_activity > config.timeout then
                        c.wrapper.socket:close()
                    else
                        table.insert(new_clients, c)
                    end
                end
            end
            clients = new_clients
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

    return instance, config
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

return server
