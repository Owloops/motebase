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
        local users_id, tags_id

        before_each(function()
            users_id = collections.create("users", {
                name = { type = "string", required = true },
            })
            collections.create("posts", {
                title = { type = "string", required = true },
                author = { type = "relation", collectionId = users_id },
            })
            tags_id = collections.create("tags", {
                name = { type = "string", required = true },
            })
            collections.create("articles", {
                title = { type = "string", required = true },
                tags = { type = "relation", collectionId = tags_id, multiple = true },
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

    describe("export", function()
        it("exports all collections", function()
            collections.create("posts", {
                title = { type = "string", required = true },
            }, { listRule = "" })
            collections.create("users", {
                name = { type = "string" },
            }, { viewRule = "@request.auth.id != ''" })

            local exported = collections.export()
            assert.are.equal(2, #exported)

            assert.are.equal("posts", exported[1].name)
            assert.is_truthy(exported[1].id)
            assert.is_truthy(exported[1].schema.title)
            assert.are.equal("", exported[1].listRule)

            assert.are.equal("users", exported[2].name)
            assert.is_truthy(exported[2].id)
            assert.are.equal("@request.auth.id != ''", exported[2].viewRule)
        end)

        it("excludes created_at from export", function()
            collections.create("posts", { title = { type = "string" } })
            local exported = collections.export()

            assert.is_nil(exported[1].created_at)
        end)

        it("returns empty array when no collections", function()
            local exported = collections.export()
            assert.are.equal(0, #exported)
        end)
    end)

    describe("import", function()
        it("creates new collections from import", function()
            local ok = collections.import_collections({
                {
                    id = "abc123def456ghi",
                    name = "posts",
                    type = "base",
                    schema = { title = { type = "string", required = true } },
                    listRule = "",
                },
            })
            assert.is_true(ok)

            local col = collections.get("posts")
            assert.is_truthy(col)
            assert.are.equal("abc123def456ghi", col.id)
            assert.is_truthy(col.schema.title)
        end)

        it("updates existing collection by ID", function()
            local id = collections.create("posts", {
                title = { type = "string" },
            }, { listRule = "" })

            local ok = collections.import_collections({
                {
                    id = id,
                    name = "posts",
                    type = "base",
                    schema = {
                        title = { type = "string" },
                        body = { type = "text" },
                    },
                    listRule = "@request.auth.id != ''",
                },
            })
            assert.is_true(ok)

            local col = collections.get("posts")
            assert.is_truthy(col.schema.body)
            assert.are.equal("@request.auth.id != ''", col.listRule)
        end)

        it("renames collection when ID matches but name differs", function()
            local id = collections.create("old_posts", {
                title = { type = "string" },
            })

            local ok = collections.import_collections({
                {
                    id = id,
                    name = "new_posts",
                    type = "base",
                    schema = { title = { type = "string" } },
                },
            })
            assert.is_true(ok)

            assert.is_nil(collections.get("old_posts"))
            local col = collections.get("new_posts")
            assert.is_truthy(col)
            assert.are.equal(id, col.id)
        end)

        it("preserves data when renaming collection", function()
            local id = collections.create("old_posts", {
                title = { type = "string" },
            })
            collections.create_record("old_posts", { title = "Test Post" })

            collections.import_collections({
                {
                    id = id,
                    name = "new_posts",
                    type = "base",
                    schema = { title = { type = "string" } },
                },
            })

            local record = collections.get_record("new_posts", 1)
            assert.is_truthy(record)
            assert.are.equal("Test Post", record.title)
        end)

        it("rejects import when name conflicts with different ID", function()
            collections.create("posts", { title = { type = "string" } })

            local ok, errors = collections.import_collections({
                {
                    id = "different_id_123",
                    name = "posts",
                    type = "base",
                    schema = { title = { type = "string" } },
                },
            })
            assert.is_nil(ok)
            assert.is_truthy(errors)
            assert.are.equal("name already used by another collection", errors[1].error)
        end)

        it("rejects field type changes", function()
            local id = collections.create("posts", {
                title = { type = "string" },
            })

            local ok, errors = collections.import_collections({
                {
                    id = id,
                    name = "posts",
                    type = "base",
                    schema = { title = { type = "number" } },
                },
            })
            assert.is_nil(ok)
            assert.is_truthy(errors)
            assert.are.equal("field type cannot be changed", errors[1].error)
            assert.are.equal("title", errors[1].field)
        end)

        it("deletes missing collections when deleteMissing is true", function()
            local id1 = collections.create("keep", { title = { type = "string" } })
            collections.create("delete_me", { name = { type = "string" } })

            local ok = collections.import_collections({
                {
                    id = id1,
                    name = "keep",
                    type = "base",
                    schema = { title = { type = "string" } },
                },
            }, true)
            assert.is_true(ok)

            assert.is_truthy(collections.get("keep"))
            assert.is_nil(collections.get("delete_me"))
        end)

        it("keeps missing collections when deleteMissing is false", function()
            local id1 = collections.create("keep", { title = { type = "string" } })
            collections.create("also_keep", { name = { type = "string" } })

            local ok = collections.import_collections({
                {
                    id = id1,
                    name = "keep",
                    type = "base",
                    schema = { title = { type = "string" } },
                },
            }, false)
            assert.is_true(ok)

            assert.is_truthy(collections.get("keep"))
            assert.is_truthy(collections.get("also_keep"))
        end)

        it("rolls back all changes on error", function()
            local id = collections.create("posts", {
                title = { type = "string" },
            })

            local ok = collections.import_collections({
                {
                    id = id,
                    name = "posts",
                    type = "base",
                    schema = { title = { type = "string" }, body = { type = "text" } },
                },
                {
                    id = "new_id_1234567",
                    name = "posts",
                    type = "base",
                    schema = { name = { type = "string" } },
                },
            })
            assert.is_nil(ok)

            local col = collections.get("posts")
            assert.is_nil(col.schema.body)
        end)

        it("handles empty import with deleteMissing", function()
            collections.create("posts", { title = { type = "string" } })

            local ok = collections.import_collections({}, true)
            assert.is_true(ok)

            assert.is_nil(collections.get("posts"))
        end)

        it("handles empty import without deleteMissing", function()
            collections.create("posts", { title = { type = "string" } })

            local ok = collections.import_collections({}, false)
            assert.is_true(ok)

            assert.is_truthy(collections.get("posts"))
        end)
    end)

    describe("relation collectionId", function()
        it("requires collectionId for relation fields", function()
            collections.create("users", { name = { type = "string" } })

            local ok, err = collections.create("posts", {
                title = { type = "string" },
                author = { type = "relation" },
            })

            assert.is_nil(ok)
            assert.is_table(err)
            assert.are.equal("author", err[1].field)
            assert.matches("requires collectionId", err[1].error)
        end)

        it("validates collectionId exists", function()
            local ok, err = collections.create("posts", {
                title = { type = "string" },
                author = { type = "relation", collectionId = "nonexistent123" },
            })

            assert.is_nil(ok)
            assert.is_table(err)
            assert.are.equal("author", err[1].field)
            assert.matches("not found", err[1].error)
        end)

        it("creates relation with valid collectionId", function()
            local users_id = collections.create("users", { name = { type = "string" } })

            local posts_id = collections.create("posts", {
                title = { type = "string" },
                author = { type = "relation", collectionId = users_id },
            })

            assert.is_truthy(posts_id)

            local posts = collections.get("posts")
            assert.are.equal(users_id, posts.schema.author.collectionId)
        end)

        it("prevents changing collectionId on existing relation", function()
            local users_id = collections.create("users", { name = { type = "string" } })
            local admins_id = collections.create("admins", { name = { type = "string" } })

            collections.create("posts", {
                title = { type = "string" },
                author = { type = "relation", collectionId = users_id },
            })

            local ok, err = collections.update("posts", {
                schema = {
                    title = { type = "string" },
                    author = { type = "relation", collectionId = admins_id },
                },
            })

            assert.is_nil(ok)
            assert.is_table(err)
            assert.are.equal("author", err[1].field)
            assert.matches("cannot be changed", err[1].error)
        end)

        it("allows adding new relation field on update", function()
            local users_id = collections.create("users", { name = { type = "string" } })
            collections.create("posts", { title = { type = "string" } })

            local updated, err = collections.update("posts", {
                schema = {
                    title = { type = "string" },
                    author = { type = "relation", collectionId = users_id },
                },
            })

            assert.is_nil(err)
            assert.is_truthy(updated)
            assert.are.equal(users_id, updated.schema.author.collectionId)
        end)

        it("survives collection rename", function()
            local users_id = collections.create("users", { name = { type = "string" } })

            collections.create("posts", {
                title = { type = "string" },
                author = { type = "relation", collectionId = users_id },
            })

            local posts = collections.get("posts")
            assert.are.equal(users_id, posts.schema.author.collectionId)
        end)
    end)
end)
