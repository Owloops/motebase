local db = require("motebase.db")
local server = require("motebase.server")
local router = require("motebase.router")
local collections = require("motebase.collections")
local auth = require("motebase.auth")
local files = require("motebase.files")
local realtime = require("motebase.realtime")
local rules = require("motebase.rules")
local ratelimit = require("motebase.ratelimit")
local oauth = require("motebase.oauth")
local jwt = require("motebase.jwt")
local url_util = require("motebase.utils.url")
local cjson = require("cjson")
local admin = require("motebase.admin")
local settings = require("motebase.settings")
local logs = require("motebase.logs")
local migrations = require("motebase.migrations")
local jobs = require("motebase.jobs")
local cron = require("motebase.cron")

local motebase = {}

local function normalize_null(value)
    if value == cjson.null then return nil end
    return value
end

-- rules --

local function build_rule_context(ctx, record, body)
    local auth_ctx = nil
    if ctx.user and ctx.user.sub then
        local user = auth.get_user(ctx.user.sub)
        if user then auth_ctx = {
            id = tostring(user.id),
            email = user.email,
        } end
    end

    return {
        auth = auth_ctx or { id = "" },
        body = body or {},
        record = record,
        query = url_util.parse_query(ctx.query_string),
        headers = ctx.headers or {},
        method = ctx.method or "GET",
        context = ctx.context or "default",
    }
end

local function check_rule(rule_str, ctx, record, body)
    if rule_str == nil then
        if ctx.user and auth.is_superuser(ctx.user) then return true end
        return false, 403, "forbidden"
    end

    if rule_str == "" then return true end

    local ast, parse_err = rules.parse(rule_str)
    if not ast then return false, 500, "invalid rule: " .. (parse_err or "unknown") end

    local rule_ctx = build_rule_context(ctx, record, body)
    local ok = rules.check(ast, rule_ctx)

    return ok
end

local function check_list_rule_and_filter(rule_str, ctx)
    if rule_str == nil then
        if ctx.user and auth.is_superuser(ctx.user) then return true, nil end
        return false, nil, 403, "forbidden"
    end

    if rule_str == "" then return true, nil end

    local ast, parse_err = rules.parse(rule_str)
    if not ast then return false, nil, 500, "invalid rule: " .. (parse_err or "unknown") end

    local auth_ast = rules.extract_auth_conditions(ast)
    if auth_ast then
        local rule_ctx = build_rule_context(ctx, nil, nil)
        local ok = rules.check(auth_ast, rule_ctx)
        if not ok then return false, nil end
    end

    local record_ast = rules.extract_record_conditions(ast)
    if record_ast then
        local sql, params = rules.to_sql_filter(record_ast, {})
        if sql then return true, { sql = sql, params = params } end
    end

    return true, nil
end

-- handlers --

local function handle_health(ctx)
    server.json(ctx, 200, { status = "ok" })
end

local function handle_create_collection(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local name = ctx.body.name
    local col_schema = ctx.body.schema

    if not name then
        server.error(ctx, 400, "name required")
        return
    end

    if not col_schema or type(col_schema) ~= "table" then
        server.error(ctx, 400, "schema required")
        return
    end

    local col_rules = {
        listRule = normalize_null(ctx.body.listRule),
        viewRule = normalize_null(ctx.body.viewRule),
        createRule = normalize_null(ctx.body.createRule),
        updateRule = normalize_null(ctx.body.updateRule),
        deleteRule = normalize_null(ctx.body.deleteRule),
    }

    local col_type = ctx.body.type

    local ok, err = collections.create(name, col_schema, col_rules, col_type)
    if not ok then
        server.error(ctx, 400, err)
        return
    end

    local collection = collections.get(name)
    server.json(ctx, 201, collection)
end

local function handle_update_collection(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local name = ctx.params.name

    local updates = {
        schema = ctx.body.schema,
        listRule = ctx.body.listRule,
        viewRule = ctx.body.viewRule,
        createRule = ctx.body.createRule,
        updateRule = ctx.body.updateRule,
        deleteRule = ctx.body.deleteRule,
    }

    local collection, err = collections.update(name, updates)
    if not collection then
        server.error(ctx, 400, err)
        return
    end

    server.json(ctx, 200, collection)
end

local function handle_list_collections(ctx)
    local list = collections.list()
    server.json(ctx, 200, { items = list or {} })
end

local function handle_delete_collection(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local name = ctx.params.name
    local ok, err = collections.delete(name)
    if not ok then
        server.error(ctx, 404, err)
        return
    end
    server.json(ctx, 200, { deleted = true })
end

local function handle_export_collections(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local exported = collections.export()
    server.json(ctx, 200, exported)
end

local function handle_import_collections(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local import_data = ctx.body.collections
    local delete_missing = ctx.body.deleteMissing == true

    if not import_data or type(import_data) ~= "table" then
        server.error(ctx, 400, "collections array required")
        return
    end

    local ok, errors = collections.import_collections(import_data, delete_missing)
    if not ok then
        server.json(ctx, 400, { error = "import failed", details = errors })
        return
    end

    server.json(ctx, 204, nil)
end

local function handle_list_records(ctx)
    local name = ctx.params.name

    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local rule_ok, rule_filter, rule_code, rule_msg = check_list_rule_and_filter(collection.listRule, ctx)
    if not rule_ok then
        if rule_code == 403 then
            server.error(ctx, 403, rule_msg)
        else
            server.json(ctx, 200, { page = 1, perPage = 20, totalItems = 0, totalPages = 0, items = {} })
        end
        return
    end
    local result, err = collections.list_records(name, ctx.query_string, rule_filter)
    if not result then
        server.error(ctx, 400, err)
        return
    end

    server.json(ctx, 200, result)
end

local function handle_get_record(ctx)
    local name = ctx.params.name
    local id = tonumber(ctx.params.id)

    if not id then
        server.error(ctx, 400, "invalid id")
        return
    end

    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local record = collections.get_record(name, id)
    if not record then
        server.error(ctx, 404, "record not found")
        return
    end

    local rule_ok, rule_code, rule_msg = check_rule(collection.viewRule, ctx, record, nil)
    if not rule_ok then
        if rule_code == 403 then
            server.error(ctx, 403, rule_msg)
        else
            server.error(ctx, 404, "record not found")
        end
        return
    end

    local expand_str
    if ctx.query_string then
        expand_str = ctx.query_string:match("expand=([^&]+)")
        if expand_str then expand_str = url_util.decode(expand_str) end
    end

    if expand_str then record = collections.get_record(name, id, expand_str) end

    server.json(ctx, 200, record)
end

local function handle_create_record(ctx)
    local name = ctx.params.name

    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local multipart_parts = ctx.is_multipart and ctx.body or nil
    local json_data = ctx.is_multipart and {} or ctx.body

    local rule_ok, rule_code, rule_msg = check_rule(collection.createRule, ctx, nil, json_data)
    if not rule_ok then
        if rule_code == 403 then
            server.error(ctx, 403, rule_msg)
        else
            server.error(ctx, 400, "create not allowed")
        end
        return
    end

    local record, err = collections.create_record(name, json_data, multipart_parts, ctx)
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

    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local existing = collections.get_record(name, id)
    if not existing then
        server.error(ctx, 404, "record not found")
        return
    end

    local multipart_parts = ctx.is_multipart and ctx.body or nil
    local json_data = ctx.is_multipart and {} or ctx.body

    local rule_ok, rule_code, rule_msg = check_rule(collection.updateRule, ctx, existing, json_data)
    if not rule_ok then
        if rule_code == 403 then
            server.error(ctx, 403, rule_msg)
        else
            server.error(ctx, 404, "record not found")
        end
        return
    end

    local record, err = collections.update_record(name, id, json_data, multipart_parts, ctx)
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

    local collection = collections.get(name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local existing = collections.get_record(name, id)
    if not existing then
        server.error(ctx, 404, "record not found")
        return
    end

    local rule_ok, rule_code, rule_msg = check_rule(collection.deleteRule, ctx, existing, nil)
    if not rule_ok then
        if rule_code == 403 then
            server.error(ctx, 403, rule_msg)
        else
            server.error(ctx, 404, "record not found")
        end
        return
    end

    local ok, err = collections.delete_record(name, id, ctx)
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

local function handle_request_password_reset(ctx)
    local app_url = ctx.body.app_url or ctx.config.app_url
    auth.request_password_reset(ctx.body.email, app_url)
    server.json(ctx, 204, nil)
end

local function handle_confirm_password_reset(ctx)
    local ok, err = auth.confirm_password_reset(ctx.body.token, ctx.body.password)
    if not ok then
        server.error(ctx, 400, err)
        return
    end
    server.json(ctx, 204, nil)
end

local function handle_request_verification(ctx)
    if not ctx.user then
        server.error(ctx, 401, ctx.auth_error or "unauthorized")
        return
    end

    local app_url = ctx.body.app_url or ctx.config.app_url
    local ok, err = auth.request_verification(ctx.user.sub, app_url)
    if not ok then
        server.error(ctx, 400, err)
        return
    end
    server.json(ctx, 204, nil)
end

local function handle_confirm_verification(ctx)
    local ok, err = auth.confirm_verification(ctx.body.token)
    if not ok then
        server.error(ctx, 400, err)
        return
    end
    server.json(ctx, 204, nil)
end

local function handle_oauth_providers(ctx)
    server.json(ctx, 200, { providers = oauth.list_providers() })
end

local function handle_oauth_redirect(ctx)
    local provider = ctx.params.provider
    if not oauth.is_enabled(provider) then
        server.error(ctx, 400, "provider not configured")
        return
    end

    local auth_url, err = oauth.get_auth_url(provider)
    if not auth_url then
        server.error(ctx, 500, err)
        return
    end

    server.redirect(ctx, auth_url)
end

local function handle_oauth_callback(ctx)
    local provider = ctx.params.provider
    local query = url_util.parse_query(ctx.query_string)
    local code = query.code
    local state = query.state

    if not code then
        server.error(ctx, 400, "missing code parameter")
        return
    end

    local access_token, err = oauth.exchange_code(provider, code, state)
    if not access_token then
        server.error(ctx, 400, err)
        return
    end

    local user_info, info_err = oauth.get_user_info(provider, access_token)
    if not user_info then
        server.error(ctx, 400, info_err)
        return
    end

    local user, user_err = auth.find_or_create_oauth_user(user_info.email, provider, user_info.provider_id)
    if not user then
        server.error(ctx, 500, user_err)
        return
    end

    local token = jwt.create_token(user.id, ctx.config.secret, { expires_in = ctx.config.token_expires_in })

    server.json(ctx, 200, {
        token = token,
        user = {
            id = user.id,
            email = user.email,
        },
    })
end

local function handle_file_token(ctx)
    if not ctx.user then
        server.error(ctx, 401, ctx.auth_error or "unauthorized")
        return
    end

    local token, expires = files.create_token()
    if not token then
        server.error(ctx, 500, "failed to create token")
        return
    end

    server.json(ctx, 200, { token = token, expires = expires })
end

local function is_file_protected(collection_name, record, filename)
    local collection = collections.get(collection_name)
    if not collection or not collection.schema then return false end

    for field_name, field_def in pairs(collection.schema) do
        if field_def.type == "file" and field_def.protected then
            local field_data = record[field_name]
            if field_data then
                local file_info = files.deserialize(field_data)
                if file_info and file_info.filename == filename then return true end
            end
        end
    end

    return false
end

local function get_token_from_query(query_string)
    if not query_string then return nil end
    local token = query_string:match("token=([^&]+)")
    return token
end

local function handle_realtime_connect(ctx)
    local client = realtime.broker.create_client()
    if ctx.user then client:set_auth(ctx.user) end
    server.sse(ctx, client)
end

local MAX_SUBSCRIPTIONS = 1000
local MAX_SUBSCRIPTION_LENGTH = 2500

local function handle_realtime_subscribe(ctx)
    local client_id = ctx.body and ctx.body.clientId
    local subscriptions = ctx.body and ctx.body.subscriptions

    if not client_id or type(client_id) ~= "string" or #client_id == 0 or #client_id > 255 then
        server.error(ctx, 400, "clientId must be 1-255 characters")
        return
    end

    local client = realtime.broker.get_client(client_id)
    if not client then
        server.error(ctx, 404, "client not found")
        return
    end

    if subscriptions then
        if type(subscriptions) ~= "table" then
            server.error(ctx, 400, "subscriptions must be an array")
            return
        end
        if #subscriptions > MAX_SUBSCRIPTIONS then
            server.error(ctx, 400, "too many subscriptions (max " .. MAX_SUBSCRIPTIONS .. ")")
            return
        end
        for i = 1, #subscriptions do
            if type(subscriptions[i]) ~= "string" or #subscriptions[i] > MAX_SUBSCRIPTION_LENGTH then
                server.error(ctx, 400, "subscription must be string <= " .. MAX_SUBSCRIPTION_LENGTH .. " chars")
                return
            end
        end
    end

    if ctx.user then
        local client_auth = client:get_auth()
        if client_auth and client_auth.sub ~= ctx.user.sub then
            server.error(ctx, 403, "auth mismatch")
            return
        end
        client:set_auth(ctx.user)
    end

    client:unsubscribe()
    if subscriptions then client:subscribe(subscriptions) end

    server.json(ctx, 204, nil)
end

local function handle_file_download(ctx)
    local collection_name = ctx.params.collection
    local record_id = tonumber(ctx.params.record)
    local filename = ctx.params.filename

    if not record_id then
        server.error(ctx, 400, "invalid record id")
        return
    end

    local collection = collections.get(collection_name)
    if not collection then
        server.error(ctx, 404, "collection not found")
        return
    end

    local record = collections.get_record(collection_name, record_id)
    if not record then
        server.error(ctx, 404, "not found")
        return
    end

    if is_file_protected(collection_name, record, filename) then
        local token = get_token_from_query(ctx.query_string)
        if not token then
            server.error(ctx, 401, "file token required")
            return
        end

        local payload, err = files.verify_token(token)
        if not payload then
            server.error(ctx, 401, err or "invalid token")
            return
        end
    end

    local data = files.read(collection_name, record_id, filename)
    if not data then
        server.error(ctx, 404, "not found")
        return
    end

    local mime_type = files.detect_mime_type(filename)
    server.file(ctx, 200, data, filename, mime_type)
end

-- settings handlers --

local function handle_get_settings(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local all_settings = settings.get_all()
    local storage_config = settings.get_storage_config()

    server.json(ctx, 200, {
        settings = all_settings,
        storage = storage_config,
    })
end

local function handle_update_settings(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    if not ctx.body or type(ctx.body) ~= "table" then
        server.error(ctx, 400, "invalid request body")
        return
    end

    local updated, err = settings.update(ctx.body)
    if not updated then
        server.error(ctx, 400, err)
        return
    end

    server.json(ctx, 200, { settings = updated })
end

-- logs handlers --

local function handle_get_logs(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local query = url_util.parse_query(ctx.query_string)

    local result = logs.list({
        page = tonumber(query.page) or 1,
        per_page = tonumber(query.perPage) or 50,
        status = query.status,
        method = query.method,
        path = query.path,
        user_id = query.user_id,
        from = query.from and tonumber(query.from),
        to = query.to and tonumber(query.to),
    })

    server.json(ctx, 200, result)
end

local function handle_get_logs_stats(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    local stats = logs.get_stats()
    server.json(ctx, 200, stats)
end

local function handle_clear_logs(ctx)
    if not ctx.user or not auth.is_superuser(ctx.user) then
        server.error(ctx, 403, "superuser required")
        return
    end

    logs.clear()
    server.json(ctx, 200, { cleared = true })
end

-- routes --

local function setup_routes()
    router.get("/api/health", handle_health)

    router.post("/api/collections", handle_create_collection)
    router.get("/api/collections", handle_list_collections)
    router.get("/api/collections/export", handle_export_collections)
    router.post("/api/collections/import", handle_import_collections)
    router.patch("/api/collections/:name", handle_update_collection)
    router.delete("/api/collections/:name", handle_delete_collection)

    router.get("/api/collections/:name/records", handle_list_records)
    router.get("/api/collections/:name/records/:id", handle_get_record)
    router.post("/api/collections/:name/records", handle_create_record)
    router.patch("/api/collections/:name/records/:id", handle_update_record)
    router.delete("/api/collections/:name/records/:id", handle_delete_record)

    router.post("/api/auth/register", handle_register)
    router.post("/api/auth/login", handle_login)
    router.get("/api/auth/me", handle_me)
    router.post("/api/auth/request-password-reset", handle_request_password_reset)
    router.post("/api/auth/confirm-password-reset", handle_confirm_password_reset)
    router.post("/api/auth/request-verification", handle_request_verification)
    router.post("/api/auth/confirm-verification", handle_confirm_verification)
    router.get("/api/auth/oauth/providers", handle_oauth_providers)
    router.get("/api/auth/oauth/:provider", handle_oauth_redirect)
    router.get("/api/auth/oauth/:provider/callback", handle_oauth_callback)

    router.post("/api/files/token", handle_file_token)
    router.get("/api/files/:collection/:record/:filename", handle_file_download)

    router.get("/api/realtime", handle_realtime_connect)
    router.post("/api/realtime", handle_realtime_subscribe)

    router.get("/api/settings", handle_get_settings)
    router.patch("/api/settings", handle_update_settings)

    router.get("/api/logs", handle_get_logs)
    router.get("/api/logs/stats", handle_get_logs_stats)
    router.delete("/api/logs", handle_clear_logs)

    admin.register_routes(router)
end

-- public api --

function motebase.start(config)
    config = config or {}
    config.db_path = config.db_path or os.getenv("MOTEBASE_DB") or "./motebase.db"
    config.storage_path = config.storage_path or os.getenv("MOTEBASE_STORAGE") or "./storage"
    config.max_file_size = config.max_file_size or tonumber(os.getenv("MOTEBASE_MAX_FILE_SIZE")) or (10 * 1024 * 1024)

    local ok, err = db.open(config.db_path)
    if not ok then return nil, err end

    local migrate_ok, migrate_err = migrations.run()
    if not migrate_ok then return nil, migrate_err end

    local init_ok, init_err = collections.init()
    if not init_ok then return nil, init_err end

    local auth_ok, auth_err = auth.init()
    if not auth_ok then return nil, auth_err end

    auth.configure({
        superuser = config.superuser or os.getenv("MOTEBASE_SUPERUSER"),
    })

    files.configure({
        storage_path = config.storage_path,
        max_file_size = config.max_file_size,
        secret = config.secret or os.getenv("MOTEBASE_SECRET") or "change-me-in-production",
        storage_backend = config.storage_backend or os.getenv("MOTEBASE_STORAGE_BACKEND") or "local",
        s3_bucket = config.s3_bucket or os.getenv("MOTEBASE_S3_BUCKET"),
        s3_region = config.s3_region or os.getenv("MOTEBASE_S3_REGION"),
        s3_endpoint = config.s3_endpoint or os.getenv("MOTEBASE_S3_ENDPOINT"),
        s3_access_key = config.s3_access_key or os.getenv("MOTEBASE_S3_ACCESS_KEY"),
        s3_secret_key = config.s3_secret_key or os.getenv("MOTEBASE_S3_SECRET_KEY"),
        s3_path_style = config.s3_path_style or os.getenv("MOTEBASE_S3_PATH_STYLE") == "true",
        s3_use_ssl = config.s3_use_ssl ~= false and os.getenv("MOTEBASE_S3_USE_SSL") ~= "false",
    })
    local files_ok, files_err = files.init()
    if not files_ok then return nil, files_err end

    local admin_ok, admin_err = admin.init()
    if not admin_ok then return nil, admin_err end

    local settings_ok, settings_err = settings.init()
    if not settings_ok then return nil, settings_err end

    local logs_ok, logs_err = logs.init()
    if not logs_ok then return nil, logs_err end

    -- Configure logs if disabled via env
    if os.getenv("MOTEBASE_REQUEST_LOGS") == "0" then logs.configure({ enabled = false }) end

    local ratelimit_val = config.ratelimit or tonumber(os.getenv("MOTEBASE_RATELIMIT"))
    if ratelimit_val then ratelimit.set_global_limit(ratelimit_val) end

    config.max_concurrent = config.max_concurrent or tonumber(os.getenv("MOTEBASE_MAX_CONNECTIONS"))

    setup_routes()

    cron.register_builtin_jobs()
    cron.start()

    local srv, srv_err = server.create(config)
    if not srv then return nil, srv_err end
    return srv
end

function motebase.stop()
    cron.stop()
    db.close()
    router.clear()
end

-- jobs api --

function motebase.queue(name, payload, options)
    return jobs.queue(name, payload, options)
end

function motebase.on_job(name, handler)
    return jobs.register(name, handler)
end

return motebase
