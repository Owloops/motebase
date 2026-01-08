local server = require("motebase.server")

local admin = {}

local dev_mode = os.getenv("MOTEBASE_DEV") == "1"

local content_cache = {
    html = nil,
    css = nil,
    js = nil,
}

local mime_types = {
    css = "text/css; charset=utf-8",
    js = "application/javascript; charset=utf-8",
    html = "text/html; charset=utf-8",
}

local admin_path = nil
local embed = nil

local function load_file_fs(filename)
    if not admin_path then return nil end
    local file = io.open(admin_path .. filename, "r")
    if file then
        local content = file:read("*a")
        file:close()
        return content
    end
    return nil
end

local function load_file_embed(filename)
    if embed then return embed.read("motebase/admin/" .. filename) end
    return nil
end

local function load_file(filename)
    local content = load_file_fs(filename)
    if content then return content end
    return load_file_embed(filename)
end

local function get_file(name)
    if dev_mode then return load_file("admin." .. name) end
    return content_cache[name]
end

function admin.init()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then admin_path = source:sub(2):match("(.*/)") end

    local ok, embed_module = pcall(require, "luast.embed")
    if ok then embed = embed_module end

    content_cache.html = load_file("admin.html")
    content_cache.css = load_file("admin.css")
    content_cache.js = load_file("admin.js")

    if not content_cache.html then return nil, "failed to load admin.html" end
    if not content_cache.css then return nil, "failed to load admin.css" end
    if not content_cache.js then return nil, "failed to load admin.js" end

    if dev_mode then print("[admin] dev mode enabled - files will reload on each request") end

    return true
end

local function serve_admin(ctx)
    local content = get_file("html")
    if not content then return server.error(ctx, 500, "admin UI not loaded") end
    ctx._response_headers["Cache-Control"] = "no-cache"
    server.html(ctx, 200, content)
end

local function serve_css(ctx)
    local content = get_file("css")
    if not content then return server.error(ctx, 500, "admin CSS not loaded") end
    ctx._status = 200
    ctx._response_headers["Content-Type"] = mime_types.css
    ctx._response_headers["Cache-Control"] = dev_mode and "no-cache" or "public, max-age=31536000"
    ctx._response_body = content
end

local function serve_js(ctx)
    local content = get_file("js")
    if not content then return server.error(ctx, 500, "admin JS not loaded") end
    ctx._status = 200
    ctx._response_headers["Content-Type"] = mime_types.js
    ctx._response_headers["Cache-Control"] = dev_mode and "no-cache" or "public, max-age=31536000"
    ctx._response_body = content
end

function admin.register_routes(router)
    router.get("/_/", serve_admin)
    router.get("/_/login", serve_admin)
    router.get("/_/admin.css", serve_css)
    router.get("/_/admin.js", serve_js)
end

return admin
