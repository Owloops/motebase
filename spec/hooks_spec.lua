local db = require("motebase.db")
local collections = require("motebase.collections")
local hooks = require("motebase.hooks")

describe("hooks", function()
    before_each(function()
        db.open(":memory:")
        collections.init()
        hooks.reset()
        collections.create("posts", {
            title = { type = "string", required = true },
            status = { type = "string" },
        })
    end)

    after_each(function()
        hooks.reset()
        db.close()
    end)

    describe("before_create", function()
        it("modifies record before insert", function()
            hooks.before_create("posts", function(record)
                record.title = "[HOOK] " .. record.title
                return record
            end)

            local record = collections.create_record("posts", { title = "Hello" })
            assert.are.equal("[HOOK] Hello", record.title)
        end)

        it("can cancel with error", function()
            hooks.before_create("posts", function()
                return nil, "creation blocked"
            end)

            local record, err = collections.create_record("posts", { title = "Hello" })
            assert.is_nil(record)
            assert.are.equal("creation blocked", err)
        end)

        it("receives ctx parameter", function()
            local received_ctx
            hooks.before_create("posts", function(record, ctx)
                received_ctx = ctx
                return record
            end)

            local ctx = { user = { sub = "123" } }
            collections.create_record("posts", { title = "Hello" }, nil, ctx)
            assert.are.equal("123", received_ctx.user.sub)
        end)
    end)

    describe("after_create", function()
        it("fires after insert with created record", function()
            local created_id
            hooks.after_create("posts", function(record)
                created_id = record.id
            end)

            local record = collections.create_record("posts", { title = "Hello" })
            assert.are.equal(record.id, created_id)
        end)
    end)

    describe("before_update", function()
        it("modifies data before update", function()
            local record = collections.create_record("posts", { title = "Hello" })

            hooks.before_update("posts", function(data)
                data.title = "[UPDATED] " .. data.title
                return data
            end)

            local updated = collections.update_record("posts", record.id, { title = "World" })
            assert.are.equal("[UPDATED] World", updated.title)
        end)

        it("can cancel with error", function()
            local record = collections.create_record("posts", { title = "Hello" })

            hooks.before_update("posts", function()
                return nil, "update blocked"
            end)

            local updated, err = collections.update_record("posts", record.id, { title = "World" })
            assert.is_nil(updated)
            assert.are.equal("update blocked", err)
        end)
    end)

    describe("after_update", function()
        it("fires after update with updated record", function()
            local record = collections.create_record("posts", { title = "Hello" })

            local updated_title
            hooks.after_update("posts", function(rec)
                updated_title = rec.title
            end)

            collections.update_record("posts", record.id, { title = "World" })
            assert.are.equal("World", updated_title)
        end)
    end)

    describe("before_delete", function()
        it("can cancel with error", function()
            local record = collections.create_record("posts", { title = "Hello" })

            hooks.before_delete("posts", function()
                return nil, "delete blocked"
            end)

            local ok, err = collections.delete_record("posts", record.id)
            assert.is_nil(ok)
            assert.are.equal("delete blocked", err)

            local still_exists = collections.get_record("posts", record.id)
            assert.is_truthy(still_exists)
        end)

        it("receives the record being deleted", function()
            local record = collections.create_record("posts", { title = "Hello" })

            local deleted_title
            hooks.before_delete("posts", function(rec)
                deleted_title = rec.title
                return rec
            end)

            collections.delete_record("posts", record.id)
            assert.are.equal("Hello", deleted_title)
        end)
    end)

    describe("after_delete", function()
        it("fires after delete with deleted record", function()
            local record = collections.create_record("posts", { title = "Hello" })

            local deleted_id
            hooks.after_delete("posts", function(rec)
                deleted_id = rec.id
            end)

            collections.delete_record("posts", record.id)
            assert.are.equal(record.id, deleted_id)
        end)
    end)

    describe("wildcard hooks", function()
        it("fires for all collections", function()
            collections.create("comments", { body = { type = "string" } })

            local call_count = 0
            hooks.before_create("*", function(record)
                call_count = call_count + 1
                return record
            end)

            collections.create_record("posts", { title = "Post" })
            collections.create_record("comments", { body = "Comment" })

            assert.are.equal(2, call_count)
        end)

        it("runs before collection-specific hooks", function()
            local order = {}
            hooks.before_create("*", function(record)
                table.insert(order, "wildcard")
                return record
            end)
            hooks.before_create("posts", function(record)
                table.insert(order, "specific")
                return record
            end)

            collections.create_record("posts", { title = "Hello" })
            assert.are.equal("wildcard", order[1])
            assert.are.equal("specific", order[2])
        end)
    end)

    describe("multiple hooks", function()
        it("chains hooks in registration order", function()
            hooks.before_create("posts", function(record)
                record.title = record.title .. " [1]"
                return record
            end)
            hooks.before_create("posts", function(record)
                record.title = record.title .. " [2]"
                return record
            end)

            local record = collections.create_record("posts", { title = "Hello" })
            assert.are.equal("Hello [1] [2]", record.title)
        end)

        it("stops on first error", function()
            local second_called = false
            hooks.before_create("posts", function()
                return nil, "first error"
            end)
            hooks.before_create("posts", function(record)
                second_called = true
                return record
            end)

            local _, err = collections.create_record("posts", { title = "Hello" })
            assert.are.equal("first error", err)
            assert.is_false(second_called)
        end)
    end)
end)
