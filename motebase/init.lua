local db = require("motebase.db")
local server = require("motebase.server")
local router = require("motebase.router")
local collections = require("motebase.collections")
local auth = require("motebase.auth")

local motebase = {}

-- handlers --

local function handle_health(ctx)
    server.json(ctx, 200, { status = "ok" })
end

local function handle_create_collection(ctx)
    local name = ctx.body.name
    local schema = ctx.body.schema

    if not name then
        server.error(ctx, 400, "name required")
        return
    end

    if not schema or type(schema) ~= "table" then
        server.error(ctx, 400, "schema required")
        return
    end

    local ok, err = collections.create(name, schema)
    if not ok then
        server.error(ctx, 400, err)
        return
    end

    local collection = collections.get(name)
    server.json(ctx, 201, collection)
end

local function handle_list_collections(ctx)
    local list = collections.list()
    server.json(ctx, 200, { items = list or {} })
end

local function handle_delete_collection(ctx)
    local name = ctx.params.name
    local ok, err = collections.delete(name)
    if not ok then
        server.error(ctx, 404, err)
        return
    end
    server.json(ctx, 200, { deleted = true })
end

local function handle_list_records(ctx)
    local name = ctx.params.name
    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local records = collections.list_records(name)
    server.json(ctx, 200, { items = records or {} })
end

local function handle_get_record(ctx)
    local name = ctx.params.name
    local id = tonumber(ctx.params.id)

    if not id then
        server.error(ctx, 400, "invalid id")
        return
    end

    local record = collections.get_record(name, id)
    if not record then
        server.error(ctx, 404, "record not found")
        return
    end

    server.json(ctx, 200, record)
end

local function handle_create_record(ctx)
    local name = ctx.params.name
    local record, err = collections.create_record(name, ctx.body)
    if not record then
        if type(err) == "table" then
            server.json(ctx, 400, { errors = err })
        else
            server.error(ctx, 400, err)
        end
        return
    end
    server.json(ctx, 201, record)
end

local function handle_update_record(ctx)
    local name = ctx.params.name
    local id = tonumber(ctx.params.id)

    if not id then
        server.error(ctx, 400, "invalid id")
        return
    end

    local record, err = collections.update_record(name, id, ctx.body)
    if not record then
        if type(err) == "table" then
            server.json(ctx, 400, { errors = err })
        else
            server.error(ctx, 404, err)
        end
        return
    end
    server.json(ctx, 200, record)
end

local function handle_delete_record(ctx)
    local name = ctx.params.name
    local id = tonumber(ctx.params.id)

    if not id then
        server.error(ctx, 400, "invalid id")
        return
    end

    local ok, err = collections.delete_record(name, id)
    if not ok then
        server.error(ctx, 404, err)
        return
    end
    server.json(ctx, 200, { deleted = true })
end

local function handle_register(ctx)
    local user, err = auth.register(ctx.body.email, ctx.body.password)
    if not user then
        server.error(ctx, 400, err)
        return
    end
    server.json(ctx, 201, user)
end

local function handle_login(ctx)
    local result, err = auth.login(ctx.body.email, ctx.body.password, ctx.config.secret, ctx.config.token_expires_in)
    if not result then
        server.error(ctx, 401, err)
        return
    end
    server.json(ctx, 200, result)
end

local function handle_me(ctx)
    if not ctx.user then
        server.error(ctx, 401, ctx.auth_error or "unauthorized")
        return
    end

    local user = auth.get_user(ctx.user.sub)
    if not user then
        server.error(ctx, 401, "user not found")
        return
    end
    server.json(ctx, 200, user)
end

-- routes --

local function setup_routes()
    router.get("/health", handle_health)

    router.post("/api/collections", handle_create_collection)
    router.get("/api/collections", handle_list_collections)
    router.delete("/api/collections/:name", handle_delete_collection)

    router.get("/api/collections/:name/records", handle_list_records)
    router.get("/api/collections/:name/records/:id", handle_get_record)
    router.post("/api/collections/:name/records", handle_create_record)
    router.patch("/api/collections/:name/records/:id", handle_update_record)
    router.delete("/api/collections/:name/records/:id", handle_delete_record)

    router.post("/api/auth/register", handle_register)
    router.post("/api/auth/login", handle_login)
    router.get("/api/auth/me", handle_me)
end

-- public api --

function motebase.start(config)
    config = config or {}
    config.db_path = config.db_path or os.getenv("MOTEBASE_DB") or "motebase.db"

    local ok, err = db.open(config.db_path)
    if not ok then return nil, err end

    local init_ok, init_err = collections.init()
    if not init_ok then return nil, init_err end

    local auth_ok, auth_err = auth.init()
    if not auth_ok then return nil, auth_err end

    setup_routes()

    local srv, srv_config = server.create(config)
    return srv, srv_config
end

function motebase.stop()
    db.close()
    router.clear()
end

return motebase
