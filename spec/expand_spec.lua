local db = require("motebase.db")
local collections = require("motebase.collections")
local expand = require("motebase.query.expand")

describe("expand", function()
    describe("parser", function()
        it("parses single field", function()
            local result = expand.parse("author")
            assert.are.equal(1, #result)
            assert.are.equal("author", result[1].field)
            assert.is_nil(result[1].nested)
            assert.is_nil(result[1].back_relation)
        end)

        it("parses multiple fields", function()
            local result = expand.parse("author,tags")
            assert.are.equal(2, #result)
            assert.are.equal("author", result[1].field)
            assert.are.equal("tags", result[2].field)
        end)

        it("parses nested expand", function()
            local result = expand.parse("author.company")
            assert.are.equal(1, #result)
            assert.are.equal("author", result[1].field)
            assert.is_truthy(result[1].nested)
            assert.are.equal("company", result[1].nested.field)
        end)

        it("parses deeply nested expand", function()
            local result = expand.parse("author.company.country")
            assert.are.equal("author", result[1].field)
            assert.are.equal("company", result[1].nested.field)
            assert.are.equal("country", result[1].nested.nested.field)
        end)

        it("parses back-relation", function()
            local result = expand.parse("posts_via_author")
            assert.are.equal(1, #result)
            assert.are.equal("posts", result[1].field)
            assert.are.equal("author", result[1].via)
            assert.is_true(result[1].back_relation)
        end)

        it("parses mixed expand types", function()
            local result = expand.parse("author,posts_via_user,tags.category")
            assert.are.equal(3, #result)
            assert.are.equal("author", result[1].field)
            assert.is_nil(result[1].back_relation)
            assert.are.equal("posts", result[2].field)
            assert.are.equal("user", result[2].via)
            assert.is_true(result[2].back_relation)
            assert.are.equal("tags", result[3].field)
            assert.is_truthy(result[3].nested)
        end)

        it("handles whitespace", function()
            local result = expand.parse("  author  ,  tags  ")
            assert.are.equal(2, #result)
            assert.are.equal("author", result[1].field)
            assert.are.equal("tags", result[2].field)
        end)

        it("returns nil for empty input", function()
            assert.is_nil(expand.parse(""))
            assert.is_nil(expand.parse(nil))
        end)

        it("handles underscore in field names", function()
            local result = expand.parse("created_by")
            assert.are.equal("created_by", result[1].field)
            assert.is_nil(result[1].back_relation)
        end)

        it("distinguishes _via_ pattern from underscores", function()
            local result = expand.parse("user_posts_via_created_by")
            assert.are.equal("user_posts", result[1].field)
            assert.are.equal("created_by", result[1].via)
            assert.is_true(result[1].back_relation)
        end)
    end)

    describe("fetch_and_index", function()
        before_each(function()
            db.open(":memory:")
            collections.init()
            collections.create("users", {
                name = { type = "string", required = true },
            })
            collections.create_record("users", { name = "Alice" })
            collections.create_record("users", { name = "Bob" })
            collections.create_record("users", { name = "Charlie" })
        end)

        after_each(function()
            db.close()
        end)

        it("fetches and indexes by id", function()
            local index = expand.fetch_and_index({ 1, 3 }, "users")
            assert.is_truthy(index["1"])
            assert.is_truthy(index["3"])
            assert.is_nil(index["2"])
            assert.are.equal("Alice", index["1"].name)
            assert.are.equal("Charlie", index["3"].name)
        end)

        it("returns empty table for empty ids", function()
            local index = expand.fetch_and_index({}, "users")
            assert.are.same({}, index)
        end)

        it("handles string ids", function()
            local index = expand.fetch_and_index({ "1", "2" }, "users")
            assert.is_truthy(index["1"])
            assert.is_truthy(index["2"])
        end)

        it("normalizes numeric string ids", function()
            local index = expand.fetch_and_index({ "1.0", "2.0" }, "users")
            assert.is_truthy(index["1"])
            assert.is_truthy(index["2"])
        end)
    end)

    describe("process", function()
        before_each(function()
            db.open(":memory:")
            collections.init()
            collections.create("users", {
                name = { type = "string", required = true },
            })
            collections.create("posts", {
                title = { type = "string", required = true },
                author = { type = "relation", collection = "users" },
            })
            collections.create_record("users", { name = "Alice" })
            collections.create_record("users", { name = "Bob" })
            collections.create_record("posts", { title = "Post 1", author = 1 })
            collections.create_record("posts", { title = "Post 2", author = 1 })
            collections.create_record("posts", { title = "Post 3", author = 2 })
        end)

        after_each(function()
            db.close()
        end)

        it("expands single relation", function()
            local records = collections.list_records_simple("posts", 10, 0)
            local tree = expand.parse("author")
            local result = expand.process(records, tree, "posts", collections.get, 0)

            local found_alice = false
            for _, r in ipairs(result) do
                if r.expand and r.expand.author and r.expand.author.name == "Alice" then
                    found_alice = true
                    break
                end
            end
            assert.is_true(found_alice)
        end)

        it("expands back-relation", function()
            local records = collections.list_records_simple("users", 10, 0)
            local tree = expand.parse("posts_via_author")
            local result = expand.process(records, tree, "users", collections.get, 0)

            local alice = nil
            local bob = nil
            for _, r in ipairs(result) do
                if r.name == "Alice" then alice = r end
                if r.name == "Bob" then bob = r end
            end

            assert.is_truthy(alice.expand)
            assert.is_truthy(alice.expand.posts_via_author)
            assert.are.equal(2, #alice.expand.posts_via_author)

            assert.is_truthy(bob.expand.posts_via_author)
            assert.are.equal(1, #bob.expand.posts_via_author)
        end)

        it("returns records unchanged when no relations exist", function()
            local records = { { id = 1, title = "Test", nonexistent = 1 } }
            local tree = expand.parse("nonexistent")
            local result = expand.process(records, tree, "posts", collections.get, 0)
            assert.is_nil(result[1].expand)
        end)

        it("handles empty records", function()
            local result = expand.process({}, expand.parse("author"), "posts", collections.get, 0)
            assert.are.same({}, result)
        end)

        it("respects max depth", function()
            local records = { { id = 1, author = "1" } }
            local tree = expand.parse("author")
            local result = expand.process(records, tree, "posts", collections.get, 7)
            assert.is_nil(result[1].expand)
        end)
    end)

    describe("multiple relations", function()
        before_each(function()
            db.open(":memory:")
            collections.init()
            collections.create("tags", {
                name = { type = "string", required = true },
            })
            collections.create("articles", {
                title = { type = "string", required = true },
                tags = { type = "relation", collection = "tags", multiple = true },
            })
            collections.create_record("tags", { name = "lua" })
            collections.create_record("tags", { name = "database" })
            collections.create_record("tags", { name = "api" })
        end)

        after_each(function()
            db.close()
        end)

        it("expands multiple relation field", function()
            collections.create_record("articles", { title = "Article 1", tags = { 1, 2, 3 } })

            local records = collections.list_records_simple("articles", 10, 0)
            local tree = expand.parse("tags")
            local result = expand.process(records, tree, "articles", collections.get, 0)

            assert.is_truthy(result[1].expand)
            assert.is_truthy(result[1].expand.tags)
            assert.are.equal(3, #result[1].expand.tags)
        end)

        it("handles empty multiple relation", function()
            collections.create_record("articles", { title = "No Tags" })

            local records = collections.list_records_simple("articles", 10, 0)
            local tree = expand.parse("tags")
            local result = expand.process(records, tree, "articles", collections.get, 0)

            assert.is_nil(result[1].expand)
        end)

        it("handles partial ids in multiple relation", function()
            collections.create_record("articles", { title = "Some Tags", tags = { 1, 999 } })

            local records = collections.list_records_simple("articles", 10, 0)
            local tree = expand.parse("tags")
            local result = expand.process(records, tree, "articles", collections.get, 0)

            assert.are.equal(1, #result[1].expand.tags)
            assert.are.equal("lua", result[1].expand.tags[1].name)
        end)
    end)
end)
