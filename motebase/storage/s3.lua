-- S3 Storage Backend

local s3_client = require("motebase.s3")

local s3_storage = {}

function s3_storage.create(config)
    local backend = {}

    s3_client.configure({
        bucket = config.s3_bucket,
        region = config.s3_region or "us-east-1",
        endpoint = config.s3_endpoint,
        access_key = config.s3_access_key,
        secret_key = config.s3_secret_key,
        path_style = config.s3_path_style or false,
        use_ssl = config.s3_use_ssl ~= false,
    })

    function backend.init()
        local ok, err = s3_client.test_connection()
        if not ok then return nil, err end
        return true
    end

    local function sanitize_path(path)
        return path:gsub("%.%.", ""):gsub("^/", "")
    end

    function backend.write(path, data)
        path = sanitize_path(path)
        return s3_client.put(path, data)
    end

    function backend.read(path)
        path = sanitize_path(path)
        return s3_client.get(path)
    end

    function backend.delete(path)
        path = sanitize_path(path)
        return s3_client.delete(path)
    end

    function backend.exists(path)
        path = sanitize_path(path)
        local result, err = s3_client.head(path)
        if result == nil and err then return false end
        return result
    end

    function backend.mkdir(_)
        return true
    end

    function backend.delete_dir(path)
        path = sanitize_path(path)
        if not path:match("/$") and path ~= "" then
            path = path.."/"
        end

        local keys, err = s3_client.list(path)
        if not keys then return nil, err end

        for i = 1, #keys do
            local ok, del_err = s3_client.delete(keys[i])
            if not ok then return nil, del_err end
        end

        return true
    end

    return backend
end

return s3_storage
