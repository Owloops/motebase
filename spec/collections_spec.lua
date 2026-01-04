local db = require("motebase.db")
local collections = require("motebase.collections")

describe("collections", function()
    before_each(function()
        db.open(":memory:")
        collections.init()
    end)

    after_each(function()
        db.close()
    end)

    it("creates and retrieves collection", function()
        local ok = collections.create("posts", {
            title = { type = "string", required = true },
            body = { type = "text" },
        })
        assert.is_true(ok)

        local collection = collections.get("posts")
        assert.is_truthy(collection)
        assert.are.equal("posts", collection.name)
        assert.is_truthy(collection.schema.title)
    end)

    it("rejects invalid collection names", function()
        local ok, err = collections.create("123invalid", {})
        assert.is_nil(ok)
        assert.are.equal("invalid collection name", err)

        local ok2, err2 = collections.create("_private", {})
        assert.is_nil(ok2)
        assert.are.equal("collection name cannot start with underscore", err2)

        collections.create("posts", { title = { type = "string" } })
        local ok3, err3 = collections.create("posts", { title = { type = "string" } })
        assert.is_nil(ok3)
        assert.are.equal("collection already exists", err3)
    end)

    it("lists and deletes collections", function()
        collections.create("posts", { title = { type = "string" } })
        collections.create("users", { name = { type = "string" } })

        local list = collections.list()
        assert.are.equal(2, #list)

        local ok = collections.delete("posts")
        assert.is_true(ok)
        assert.is_nil(collections.get("posts"))
    end)

    describe("records", function()
        before_each(function()
            collections.create("posts", {
                title = { type = "string", required = true },
                views = { type = "number" },
            })
        end)

        it("creates and retrieves record", function()
            local record = collections.create_record("posts", { title = "Hello", views = 10 })
            assert.is_truthy(record)
            assert.are.equal(1, record.id)
            assert.are.equal("Hello", record.title)
            assert.are.equal(10, record.views)

            local fetched = collections.get_record("posts", 1)
            assert.is_truthy(fetched)
            assert.are.equal("Hello", fetched.title)
        end)

        it("rejects record with missing required field", function()
            local record, err = collections.create_record("posts", { views = 10 })
            assert.is_nil(record)
            assert.are.equal("field is required", err.title)
        end)

        it("lists records with pagination", function()
            collections.create_record("posts", { title = "Post 1" })
            collections.create_record("posts", { title = "Post 2" })

            local result = collections.list_records("posts")
            assert.are.equal(2, #result.items)
            assert.are.equal(2, result.totalItems)
            assert.are.equal(1, result.page)
        end)

        it("updates and deletes record", function()
            collections.create_record("posts", { title = "Hello" })

            local record = collections.update_record("posts", 1, { title = "Updated" })
            assert.are.equal("Updated", record.title)

            local ok = collections.delete_record("posts", 1)
            assert.is_true(ok)
            assert.is_nil(collections.get_record("posts", 1))
        end)

        it("returns nil for non-existent record", function()
            assert.is_nil(collections.get_record("posts", 999))
        end)
    end)
end)
