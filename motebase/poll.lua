local poll_c = require("motebase.poll_c")

local poll = {}

poll._MAXFDS = poll_c._MAXFDS

-- native --

function poll.poll(sockets, timeout)
    return poll_c.poll(sockets, timeout)
end

-- select wrapper --

function poll.select(readers, writers, timeout)
    readers = readers or {}
    writers = writers or {}

    local poll_list = {}
    local sock_index = {}

    for i = 1, #readers do
        local sock = readers[i]
        local idx = #poll_list + 1
        sock_index[sock] = idx
        poll_list[idx] = { sock = sock, read = true, write = false }
    end

    for i = 1, #writers do
        local sock = writers[i]
        local idx = sock_index[sock]
        if idx then
            poll_list[idx].write = true
        else
            idx = #poll_list + 1
            poll_list[idx] = { sock = sock, read = false, write = true }
        end
    end

    if #poll_list == 0 then return {}, {} end

    local ready, err = poll_c.poll(poll_list, timeout)
    if not ready then
        if err == "timeout" then return {}, {}, err end
        return nil, nil, err
    end

    local readable, writable = {}, {}
    for i = 1, #ready do
        local entry = ready[i]
        if entry.read then readable[#readable + 1] = entry.sock end
        if entry.write then writable[#writable + 1] = entry.sock end
    end

    return readable, writable
end

return poll
