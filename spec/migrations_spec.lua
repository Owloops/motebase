local db = require("motebase.db")
local migrations = require("motebase.migrations")

describe("migrations", function()
    before_each(function()
        db.open(":memory:")
    end)

    after_each(function()
        db.close()
    end)

    describe("run", function()
        it("applies all migrations to fresh database", function()
            local ok, err = migrations.run()
            assert.is_true(ok, err)
            assert.are.equal(migrations.target_version(), migrations.current_version())
        end)

        it("creates system tables", function()
            migrations.run()

            local settings = db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='_settings'")
            assert.are.equal(1, #settings)

            local collections = db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='_collections'")
            assert.are.equal(1, #collections)

            local users = db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='_users'")
            assert.are.equal(1, #users)

            local logs = db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='_logs'")
            assert.are.equal(1, #logs)
        end)

        it("creates indexes on _logs", function()
            migrations.run()

            local indexes = db.query([[
                SELECT name FROM sqlite_master
                WHERE type='index' AND tbl_name='_logs'
                ORDER BY name
            ]])

            local index_names = {}
            for _, row in ipairs(indexes) do
                index_names[row.name] = true
            end

            assert.is_true(index_names["idx_logs_created_at"])
            assert.is_true(index_names["idx_logs_status"])
            assert.is_true(index_names["idx_logs_path"])
        end)

        it("is idempotent", function()
            migrations.run()
            local version1 = migrations.current_version()

            local ok, err = migrations.run()
            assert.is_true(ok, err)
            assert.are.equal(version1, migrations.current_version())
        end)

        it("skips already-applied migrations", function()
            migrations.run()

            db.insert("INSERT INTO _collections (name, schema) VALUES (?, ?)", { "test", "{}" })

            local ok, err = migrations.run()
            assert.is_true(ok, err)

            local rows = db.query("SELECT name FROM _collections WHERE name = ?", { "test" })
            assert.are.equal(1, #rows)
        end)
    end)

    describe("current_version", function()
        it("returns 0 for fresh database", function()
            assert.are.equal(0, migrations.current_version())
        end)

        it("returns version after migrations", function()
            migrations.run()
            assert.is_true(migrations.current_version() > 0)
        end)
    end)

    describe("target_version", function()
        it("returns number of registered migrations", function()
            assert.is_true(migrations.target_version() >= 1)
        end)
    end)
end)

describe("db.transaction", function()
    before_each(function()
        db.open(":memory:")
        db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")
    end)

    after_each(function()
        db.close()
    end)

    it("commits on success", function()
        local ok = db.transaction(function()
            db.insert("INSERT INTO test (value) VALUES (?)", { "one" })
            db.insert("INSERT INTO test (value) VALUES (?)", { "two" })
        end)

        assert.is_true(ok)

        local rows = db.query("SELECT * FROM test")
        assert.are.equal(2, #rows)
    end)

    it("rolls back on error", function()
        local ok, err = db.transaction(function()
            db.insert("INSERT INTO test (value) VALUES (?)", { "one" })
            error("intentional failure")
        end)

        assert.is_nil(ok)
        assert.is_truthy(err:match("intentional failure"))

        local rows = db.query("SELECT * FROM test")
        assert.are.equal(0, #rows)
    end)
end)
