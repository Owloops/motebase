local client_mod = require("motebase.realtime.client")
local rules = require("motebase.rules")
local auth = require("motebase.auth")

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

local function build_client_context(cl, record)
    local client_auth = cl:get_auth()
    local auth_ctx = { id = "" }

    if client_auth and client_auth.sub then
        local user = auth.get_user(client_auth.sub)
        if user then auth_ctx = {
            id = tostring(user.id),
            email = user.email,
        } end
    end

    return {
        auth = auth_ctx,
        body = {},
        record = record,
    }
end

local function check_view_rule(collection, cl, record)
    if not collection then return true end

    local view_rule = collection.viewRule

    if view_rule == nil then
        local client_auth = cl:get_auth()
        return client_auth and auth.is_superuser(client_auth)
    end

    if view_rule == "" then return true end

    local ast = rules.parse(view_rule)
    if not ast then return false end

    local ctx = build_client_context(cl, record)
    return rules.check(ast, ctx)
end

function broker.broadcast(collection_name, action, record, collection)
    if broker.client_count == 0 then return end

    local record_id = record and record.id
    local message_data = {
        action = action,
        record = record,
    }

    for _, cl in pairs(broker.clients) do
        if not cl:is_discarded() then
            local topic = cl:matches_topic(collection_name, record_id)
            if topic then
                local can_view = check_view_rule(collection, cl, record)
                if can_view then
                    cl:queue_message({
                        name = topic,
                        data = message_data,
                    })
                end
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
