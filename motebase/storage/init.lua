local storage = {}

local backend = nil

function storage.init(config)
    config = config or {}
    local backend_type = config.storage_backend or "local"

    if backend_type == "local" then
        local local_storage = require("motebase.storage.local")
        backend = local_storage.create(config)
    else
        return nil, "unknown storage backend: " .. backend_type
    end

    return backend.init()
end

function storage.write(path, data)
    if not backend then return nil, "storage not initialized" end
    return backend.write(path, data)
end

function storage.read(path)
    if not backend then return nil, "storage not initialized" end
    return backend.read(path)
end

function storage.delete(path)
    if not backend then return nil, "storage not initialized" end
    return backend.delete(path)
end

function storage.exists(path)
    if not backend then return false end
    return backend.exists(path)
end

function storage.mkdir(path)
    if not backend then return nil, "storage not initialized" end
    return backend.mkdir(path)
end

function storage.delete_dir(path)
    if not backend then return nil, "storage not initialized" end
    if backend.delete_dir then return backend.delete_dir(path) end
    return nil, "delete_dir not supported by backend"
end

function storage.get_backend()
    return backend
end

function storage.get_base_path()
    if not backend then return nil end
    return backend.base_path
end

return storage
