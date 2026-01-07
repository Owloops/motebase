local lfs = require("lfs")

local local_storage = {}

local function mkdir_recursive(path)
    local attr = lfs.attributes(path)
    if attr and attr.mode == "directory" then return true end

    local parent = path:match("(.+)/[^/]+$")
    if parent and parent ~= "" then
        local ok, err = mkdir_recursive(parent)
        if not ok then return nil, err end
    end

    local ok, err = lfs.mkdir(path)
    if not ok then
        attr = lfs.attributes(path)
        if attr and attr.mode == "directory" then return true end
        return nil, err
    end
    return true
end

local function rmdir_recursive(path)
    local attr = lfs.attributes(path)
    if not attr then return true end

    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                local full = path .. "/" .. entry
                local ok, err = rmdir_recursive(full)
                if not ok then return nil, err end
            end
        end
        return lfs.rmdir(path)
    else
        return os.remove(path)
    end
end

function local_storage.create(config)
    local base_path = config.storage_path or "./storage"

    local backend = {
        base_path = base_path,
    }

    function backend.init()
        local ok, err = backend.mkdir("")
        if not ok then return nil, err end
        return true
    end

    function backend.resolve(path)
        local safe_path = path:gsub("%.%.", ""):gsub("^/", "")
        return base_path .. "/" .. safe_path
    end

    function backend.mkdir(path)
        local full_path = backend.resolve(path)
        return mkdir_recursive(full_path)
    end

    function backend.write(path, data)
        local full_path = backend.resolve(path)
        local dir = full_path:match("(.+)/[^/]+$")
        if dir then
            local ok, err = mkdir_recursive(dir)
            if not ok then return nil, err end
        end

        local file, err = io.open(full_path, "wb")
        if not file then return nil, err end
        file:write(data)
        file:close()
        return true
    end

    function backend.read(path)
        local full_path = backend.resolve(path)
        local file, err = io.open(full_path, "rb")
        if not file then return nil, err end
        local data = file:read("*a")
        file:close()
        return data
    end

    function backend.delete(path)
        local full_path = backend.resolve(path)
        local ok, err = os.remove(full_path)
        if not ok then return nil, err end
        return true
    end

    function backend.exists(path)
        local full_path = backend.resolve(path)
        local attr = lfs.attributes(full_path)
        return attr ~= nil
    end

    function backend.delete_dir(path)
        local full_path = backend.resolve(path)
        return rmdir_recursive(full_path)
    end

    return backend
end

return local_storage
