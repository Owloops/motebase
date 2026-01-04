local lfs = require("lfs")
local storage = require("motebase.storage")

local function rmdir_recursive(path)
    local attr = lfs.attributes(path)
    if not attr then return true end

    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then rmdir_recursive(path .. "/" .. entry) end
        end
        lfs.rmdir(path)
    else
        os.remove(path)
    end
    return true
end

describe("storage", function()
    local test_path = "/tmp/motebase_storage_test"

    before_each(function()
        storage.init({ storage_path = test_path })
    end)

    after_each(function()
        rmdir_recursive(test_path)
    end)

    it("writes, reads, and checks file existence", function()
        local ok = storage.write("test/file.txt", "hello storage")
        assert.is_true(ok)

        local data = storage.read("test/file.txt")
        assert.are.equal("hello storage", data)

        assert.is_true(storage.exists("test/file.txt"))
        assert.is_false(storage.exists("missing.txt"))
    end)

    it("deletes files and directories", function()
        storage.write("todelete.txt", "content")
        assert.is_true(storage.exists("todelete.txt"))

        local ok = storage.delete("todelete.txt")
        assert.is_true(ok)
        assert.is_false(storage.exists("todelete.txt"))

        storage.mkdir("toremove/subdir")
        storage.write("toremove/subdir/file.txt", "content")

        local ok2 = storage.delete_dir("toremove")
        assert.is_true(ok2)
        assert.is_false(storage.exists("toremove/subdir/file.txt"))
    end)

    it("creates nested directories", function()
        local ok = storage.mkdir("nested/deep/path")
        assert.is_true(ok)

        storage.write("nested/deep/path/file.txt", "deep content")
        local data = storage.read("nested/deep/path/file.txt")
        assert.are.equal("deep content", data)
    end)

    it("prevents path traversal", function()
        assert.is_nil(storage.read("../../../etc/passwd"))

        storage.write("safe.txt", "safe content")
        assert.are.equal("safe content", storage.read("....safe.txt"))
        assert.are.equal("safe content", storage.read("..safe.txt"))
    end)
end)
