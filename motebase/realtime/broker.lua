local client_mod = require("motebase.realtime.client")

local broker = {
    clients = {},
    client_count = 0,
}

function broker.register(cl)
    broker.clients[cl.id] = cl
    broker.client_count = broker.client_count + 1
    return cl
end

function broker.unregister(client_id)
    local cl = broker.clients[client_id]
    if cl then
        cl:discard()
        broker.clients[client_id] = nil
        broker.client_count = broker.client_count - 1
    end
end

function broker.get_client(client_id)
    return broker.clients[client_id]
end

function broker.total_clients()
    return broker.client_count
end

function broker.all_clients()
    local result = {}
    for _, cl in pairs(broker.clients) do
        result[#result + 1] = cl
    end
    return result
end

function broker.broadcast(collection, action, record)
    if broker.client_count == 0 then return end

    local record_id = record and record.id
    local message_data = {
        action = action,
        record = record,
    }

    for _, cl in pairs(broker.clients) do
        if not cl:is_discarded() then
            local topic = cl:matches_topic(collection, record_id)
            if topic then
                cl:queue_message({
                    name = topic,
                    data = message_data,
                })
            end
        end
    end
end

function broker.create_client()
    local cl = client_mod.new()
    broker.register(cl)
    return cl
end

function broker.cleanup()
    for id, cl in pairs(broker.clients) do
        if cl:is_discarded() then
            broker.clients[id] = nil
            broker.client_count = broker.client_count - 1
        end
    end
end

return broker
