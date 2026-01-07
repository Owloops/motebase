-- Convenience helpers for common hook patterns
-- Users can also directly require() and wrap any motebase module

local collections = require("motebase.collections")

local hooks = {}

-- Store original functions
local originals = {
    create_record = collections.create_record,
    update_record = collections.update_record,
    delete_record = collections.delete_record,
}

-- Hook registries
local before_create = {}
local after_create = {}
local before_update = {}
local after_update = {}
local before_delete = {}
local after_delete = {}

-- helpers --

local function run_before_hooks(registry, collection_name, record, ctx)
    local hooks_list = registry[collection_name] or {}
    local all_hooks = registry["*"] or {}

    for _, fn in ipairs(all_hooks) do
        local result, err = fn(record, ctx)
        if err then return nil, err end
        if result then record = result end
    end

    for _, fn in ipairs(hooks_list) do
        local result, err = fn(record, ctx)
        if err then return nil, err end
        if result then record = result end
    end

    return record
end

local function run_after_hooks(registry, collection_name, record, ctx)
    local hooks_list = registry[collection_name] or {}
    local all_hooks = registry["*"] or {}

    for _, fn in ipairs(all_hooks) do
        fn(record, ctx)
    end

    for _, fn in ipairs(hooks_list) do
        fn(record, ctx)
    end
end

-- Replace collections functions with hooked versions
---@diagnostic disable-next-line: duplicate-set-field
collections.create_record = function(name, data, multipart_parts, ctx)
    local modified, err = run_before_hooks(before_create, name, data, ctx)
    if err then return nil, err end

    local record, create_err = originals.create_record(name, modified or data, multipart_parts, ctx)
    if not record then return nil, create_err end

    run_after_hooks(after_create, name, record, ctx)
    return record
end

---@diagnostic disable-next-line: duplicate-set-field
collections.update_record = function(name, id, data, multipart_parts, ctx)
    local modified, err = run_before_hooks(before_update, name, data, ctx)
    if err then return nil, err end

    local record, update_err = originals.update_record(name, id, modified or data, multipart_parts, ctx)
    if not record then return nil, update_err end

    run_after_hooks(after_update, name, record, ctx)
    return record
end

---@diagnostic disable-next-line: duplicate-set-field
collections.delete_record = function(name, id, ctx)
    local record = collections.get_record(name, id)
    if not record then return nil, "record not found" end

    local _, err = run_before_hooks(before_delete, name, record, ctx)
    if err then return nil, err end

    local ok, delete_err = originals.delete_record(name, id, ctx)
    if not ok then return nil, delete_err end

    run_after_hooks(after_delete, name, record, ctx)
    return true
end

-- public api --

function hooks.before_create(collection, fn)
    before_create[collection] = before_create[collection] or {}
    table.insert(before_create[collection], fn)
end

function hooks.after_create(collection, fn)
    after_create[collection] = after_create[collection] or {}
    table.insert(after_create[collection], fn)
end

function hooks.before_update(collection, fn)
    before_update[collection] = before_update[collection] or {}
    table.insert(before_update[collection], fn)
end

function hooks.after_update(collection, fn)
    after_update[collection] = after_update[collection] or {}
    table.insert(after_update[collection], fn)
end

function hooks.before_delete(collection, fn)
    before_delete[collection] = before_delete[collection] or {}
    table.insert(before_delete[collection], fn)
end

function hooks.after_delete(collection, fn)
    after_delete[collection] = after_delete[collection] or {}
    table.insert(after_delete[collection], fn)
end

return hooks
