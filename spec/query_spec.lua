local filter = require("motebase.query.filter")
local sort = require("motebase.query.sort")
local query = require("motebase.query")

describe("query", function()
    describe("filter parser", function()
        it("parses comparison operators", function()
            local cases = {
                { "status='active'", "=", "active" },
                { "status!='deleted'", "!=", "deleted" },
                { "views>100", ">", 100 },
                { "views>=100", ">=", 100 },
                { "views<50", "<", 50 },
                { "views<=50", "<=", 50 },
                { "title~'hello'", "~", "hello" },
                { "title!~'spam'", "!~", "spam" },
                { "tags?='lua'", "?=", "lua" },
            }
            for _, case in ipairs(cases) do
                local ast = filter.parse(case[1])
                assert.is_truthy(ast, "failed to parse: " .. case[1])
                assert.are.equal(case[2], ast.op)
                assert.are.equal(case[3], ast.value)
            end
        end)

        it("parses value types", function()
            local ast = filter.parse('title="hello world"')
            assert.are.equal("hello world", ast.value)

            ast = filter.parse("active=true")
            assert.are.equal(true, ast.value)

            ast = filter.parse("active=false")
            assert.are.equal(false, ast.value)

            ast = filter.parse("deleted=null")
            assert.is_nil(ast.value)

            ast = filter.parse("balance>-100")
            assert.are.equal(-100, ast.value)

            ast = filter.parse("price<99.99")
            assert.are.equal(99.99, ast.value)
        end)

        it("parses logical expressions", function()
            local ast = filter.parse("status='active' && views>100")
            assert.are.equal("binary", ast.type)
            assert.are.equal("AND", ast.op)

            ast = filter.parse("status='active' || status='pending'")
            assert.are.equal("OR", ast.op)

            ast = filter.parse("(status='active' || status='pending') && views>100")
            assert.are.equal("AND", ast.op)
            assert.are.equal("OR", ast.left.op)
        end)

        it("handles whitespace and errors", function()
            local ast = filter.parse("  status  =  'active'  ")
            assert.are.equal("status", ast.field)

            local ast2, err = filter.parse("")
            assert.is_nil(ast2)
            assert.is_truthy(err)

            local ast3, err2 = filter.parse("not valid filter")
            assert.is_nil(ast3)
            assert.is_truthy(err2)
        end)
    end)

    describe("filter validation", function()
        local schema = { title = { type = "string" }, views = { type = "number" } }

        it("validates fields against schema", function()
            assert.is_nil(filter.validate(filter.parse("title='hello'"), schema))
            assert.is_nil(filter.validate(filter.parse("id=1"), schema))
            assert.is_nil(filter.validate(filter.parse("created_at>1000"), schema))

            local err = filter.validate(filter.parse("unknown='value'"), schema)
            assert.is_truthy(err:find("unknown field"))
        end)
    end)

    describe("filter to SQL", function()
        it("converts expressions to parameterized SQL", function()
            local ast = filter.parse("status='active'")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("status = ?", sql)
            assert.are.equal("active", params[1])

            ast = filter.parse("title~'hello'")
            sql, params = filter.to_sql(ast)
            assert.are.equal("title LIKE ?", sql)
            assert.are.equal("%hello%", params[1])

            ast = filter.parse("title~'hello%'")
            sql, params = filter.to_sql(ast)
            assert.are.equal("hello%", params[1])

            ast = filter.parse("status='active' && views>100")
            sql, params = filter.to_sql(ast)
            assert.are.equal("(status = ? AND views > ?)", sql)
            assert.are.equal(2, #params)

            ast = filter.parse("(status='active' || status='pending') && views>100")
            sql, params = filter.to_sql(ast)
            assert.are.equal("((status = ? OR status = ?) AND views > ?)", sql)
        end)
    end)

    describe("sort parser", function()
        local schema = { title = { type = "string" }, views = { type = "number" } }

        it("parses sort expressions", function()
            local parsed = sort.parse("title")
            assert.are.equal(1, #parsed)
            assert.are.equal("title", parsed[1].field)
            assert.are.equal("ASC", parsed[1].dir)

            parsed = sort.parse("-created_at")
            assert.are.equal("DESC", parsed[1].dir)

            parsed = sort.parse("-views,title")
            assert.are.equal(2, #parsed)
            assert.are.equal("DESC", parsed[1].dir)
            assert.are.equal("ASC", parsed[2].dir)
        end)

        it("handles empty and invalid input", function()
            assert.is_nil(sort.parse(""))

            local parsed, err = sort.parse("unknown", schema)
            assert.is_nil(parsed)
            assert.is_truthy(err:find("unknown field"))
        end)

        it("converts to SQL", function()
            local parsed = sort.parse("-views,title", schema)
            assert.are.equal("views DESC, title ASC", sort.to_sql(parsed))
        end)
    end)

    describe("query parser", function()
        local schema = { title = { type = "string" }, status = { type = "string" }, views = { type = "number" } }

        it("parses pagination parameters", function()
            local opts = query.parse("page=3")
            assert.are.equal(3, opts.page)

            opts = query.parse("")
            assert.are.equal(1, opts.page)

            opts = query.parse("perPage=50")
            assert.are.equal(50, opts.per_page)

            opts = query.parse("perPage=1000")
            assert.are.equal(500, opts.per_page)

            opts = query.parse("skipTotal=true")
            assert.is_true(opts.skip_total)
        end)

        it("parses fields, sort, and filter", function()
            local opts = query.parse("fields=id,title,status", schema)
            assert.are.equal(3, #opts.fields)

            opts = query.parse("fields=id,unknown,title", schema)
            assert.are.equal(2, #opts.fields)

            opts = query.parse("sort=-views,title", schema)
            assert.are.equal(2, #opts.sort)

            opts = query.parse("filter=status='active'", schema)
            assert.are.equal("status", opts.filter.field)

            opts = query.parse("filter=title%3D%27hello%27")
            assert.is_truthy(opts.filter)
        end)
    end)

    describe("query SQL builder", function()
        it("builds SQL queries", function()
            local built = query.build_sql("posts", { page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("SELECT %* FROM posts"))
            assert.is_truthy(built.sql:find("LIMIT %? OFFSET %?"))
            assert.is_truthy(built.count_sql:find("SELECT COUNT"))

            built = query.build_sql("posts", { fields = { "id", "title" }, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("SELECT id, title FROM posts"))

            local sorted = sort.parse("-created_at")
            built = query.build_sql("posts", { sort = sorted, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("ORDER BY created_at DESC"))

            local ast = filter.parse("status='active'")
            built = query.build_sql("posts", { filter = ast, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("WHERE status = %?"))

            built = query.build_sql("posts", { page = 1, per_page = 20, skip_total = true })
            assert.is_nil(built.count_sql)
        end)
    end)
end)
