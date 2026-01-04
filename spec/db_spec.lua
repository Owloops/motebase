local db = require("motebase.db")

describe("db", function()
    before_each(function()
        db.open(":memory:")
    end)

    after_each(function()
        db.close()
    end)

    it("opens and closes database", function()
        assert.is_truthy(db.get_connection())
        db.close()
        assert.is_nil(db.get_connection())
    end)

    it("executes SQL and returns error for invalid SQL", function()
        local ok = db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        assert.is_true(ok)

        local ok2, err = db.exec("INVALID SQL")
        assert.is_nil(ok2)
        assert.is_truthy(err)
    end)

    it("inserts, queries, updates, and deletes rows", function()
        db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")

        local id = db.insert("INSERT INTO test (name) VALUES (?)", { "alice" })
        assert.are.equal(1, id)

        local rows = db.query("SELECT * FROM test WHERE id = ?", { 1 })
        assert.are.equal(1, #rows)
        assert.are.equal("alice", rows[1].name)

        local changes = db.run("UPDATE test SET name = ? WHERE id = ?", { "bob", 1 })
        assert.are.equal(1, changes)

        rows = db.query("SELECT * FROM test WHERE id = ?", { 1 })
        assert.are.equal("bob", rows[1].name)

        changes = db.run("DELETE FROM test WHERE id = ?", { 1 })
        assert.are.equal(1, changes)

        rows = db.query("SELECT * FROM test")
        assert.are.equal(0, #rows)
    end)

    it("handles boolean binding", function()
        db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, active INTEGER)")
        db.insert("INSERT INTO test (active) VALUES (?)", { true })
        db.insert("INSERT INTO test (active) VALUES (?)", { false })

        local rows = db.query("SELECT * FROM test ORDER BY id")
        assert.are.equal(1, rows[1].active)
        assert.are.equal(0, rows[2].active)
    end)
end)
