local router = {}

local routes = {}

local function compile_pattern(path)
    local pattern = "^" .. path:gsub(":([%w_]+)", "([^/]+)") .. "$"
    local params = {}
    for param in path:gmatch(":([%w_]+)") do
        params[#params + 1] = param
    end
    return pattern, params
end

function router.add(method, path, handler)
    local pattern, param_names = compile_pattern(path)
    routes[#routes + 1] = {
        method = method,
        pattern = pattern,
        param_names = param_names,
        handler = handler,
    }
end

function router.get(path, handler)
    router.add("GET", path, handler)
end

function router.post(path, handler)
    router.add("POST", path, handler)
end

function router.patch(path, handler)
    router.add("PATCH", path, handler)
end

function router.delete(path, handler)
    router.add("DELETE", path, handler)
end

function router.match(method, path)
    for _, route in ipairs(routes) do
        if route.method == method then
            local matches = { path:match(route.pattern) }
            if #matches > 0 or path:match(route.pattern) then
                local params = {}
                for i, name in ipairs(route.param_names) do
                    params[name] = matches[i]
                end
                return route.handler, params
            end
        end
    end
    return nil
end

function router.clear()
    routes = {}
end

return router
