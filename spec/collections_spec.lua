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
        local id = collections.create("posts", {
            title = { type = "string", required = true },
            body = { type = "text" },
        })
        assert.is_truthy(id)
        assert.are.equal(15, #id)

        local collection = collections.get("posts")
        assert.is_truthy(collection)
        assert.are.equal("posts", collection.name)
        assert.are.equal(id, collection.id)
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
        assert.is_truthy(list[1].id)
        assert.is_truthy(list[2].id)

        local ok = collections.delete("posts")
        assert.is_true(ok)
        assert.is_nil(collections.get("posts"))
    end)

    it("retrieves collection by id", function()
        local id = collections.create("posts", { title = { type = "string" } })
        assert.is_truthy(id)

        local collection = collections.get_by_id(id)
        assert.is_truthy(collection)
        assert.are.equal("posts", collection.name)
        assert.are.equal(id, collection.id)

        assert.is_nil(collections.get_by_id("nonexistent123"))
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

    describe("relations", function()
        before_each(function()
            collections.create("users", {
                name = { type = "string", required = true },
            })
            collections.create("posts", {
                title = { type = "string", required = true },
                author = { type = "relation", collection = "users" },
            })
            collections.create("tags", {
                name = { type = "string", required = true },
            })
            collections.create("articles", {
                title = { type = "string", required = true },
                tags = { type = "relation", collection = "tags", multiple = true },
            })
        end)

        it("creates record with single relation", function()
            collections.create_record("users", { name = "Alice" })
            local record = collections.create_record("posts", { title = "Hello", author = 1 })

            assert.is_truthy(record)
            assert.is_truthy(record.author)
        end)

        it("creates record with multiple relation", function()
            collections.create_record("tags", { name = "lua" })
            collections.create_record("tags", { name = "database" })
            local record = collections.create_record("articles", { title = "Test", tags = { 1, 2 } })

            assert.is_truthy(record)
            assert.is_truthy(record.tags)
        end)

        it("expands single relation in list_records", function()
            collections.create_record("users", { name = "Alice" })
            collections.create_record("posts", { title = "Hello", author = 1 })

            local result = collections.list_records("posts", "expand=author")
            assert.are.equal(1, #result.items)
            assert.is_truthy(result.items[1].expand)
            assert.is_truthy(result.items[1].expand.author)
            assert.are.equal("Alice", result.items[1].expand.author.name)
        end)

        it("expands single relation in get_record", function()
            collections.create_record("users", { name = "Bob" })
            collections.create_record("posts", { title = "World", author = 1 })

            local record = collections.get_record("posts", 1, "author")
            assert.is_truthy(record.expand)
            assert.is_truthy(record.expand.author)
            assert.are.equal("Bob", record.expand.author.name)
        end)

        it("expands multiple relation", function()
            collections.create_record("tags", { name = "lua" })
            collections.create_record("tags", { name = "api" })
            collections.create_record("articles", { title = "Test", tags = { 1, 2 } })

            local result = collections.list_records("articles", "expand=tags")
            assert.is_truthy(result.items[1].expand)
            assert.is_truthy(result.items[1].expand.tags)
            assert.are.equal(2, #result.items[1].expand.tags)
        end)

        it("expands back-relation", function()
            collections.create_record("users", { name = "Alice" })
            collections.create_record("posts", { title = "Post 1", author = 1 })
            collections.create_record("posts", { title = "Post 2", author = 1 })

            local result = collections.list_records("users", "expand=posts_via_author")
            assert.is_truthy(result.items[1].expand)
            assert.is_truthy(result.items[1].expand.posts_via_author)
            assert.are.equal(2, #result.items[1].expand.posts_via_author)
        end)

        it("returns error for invalid expand syntax", function()
            collections.create_record("users", { name = "Alice" })

            local result, err = collections.list_records("users", "expand=...")
            assert.is_nil(result)
            assert.is_truthy(err)
        end)

        it("handles missing relation gracefully", function()
            collections.create_record("posts", { title = "No Author" })

            local result = collections.list_records("posts", "expand=author")
            assert.are.equal(1, #result.items)
            assert.is_nil(result.items[1].expand)
        end)

        it("handles non-existent target in expand", function()
            collections.create_record("posts", { title = "Bad Ref", author = 999 })

            local result = collections.list_records("posts", "expand=author")
            assert.are.equal(1, #result.items)
            assert.is_nil(result.items[1].expand.author)
        end)
    end)

    describe("relations with collectionId", function()
        it("expands relation using collectionId instead of collection name", function()
            local users_id = collections.create("authors", {
                name = { type = "string", required = true },
            })
            collections.create("books", {
                title = { type = "string", required = true },
                writer = { type = "relation", collectionId = users_id },
            })

            collections.create_record("authors", { name = "Hemingway" })
            collections.create_record("books", { title = "The Old Man and the Sea", writer = 1 })

            local result = collections.list_records("books", "expand=writer")
            assert.are.equal(1, #result.items)
            assert.is_truthy(result.items[1].expand)
            assert.is_truthy(result.items[1].expand.writer)
            assert.are.equal("Hemingway", result.items[1].expand.writer.name)
        end)
    end)
end)
