local filter = require("motebase.query.filter")
local sort = require("motebase.query.sort")
local query = require("motebase.query")

describe("query", function()
    describe("filter parser", function()
        it("parses simple equality", function()
            local ast = filter.parse("status='active'")
            assert.is_truthy(ast)
            assert.are.equal("comparison", ast.type)
            assert.are.equal("status", ast.field)
            assert.are.equal("=", ast.op)
            assert.are.equal("active", ast.value)
        end)

        it("parses not equal", function()
            local ast = filter.parse("status!='deleted'")
            assert.are.equal("!=", ast.op)
        end)

        it("parses greater than", function()
            local ast = filter.parse("views>100")
            assert.are.equal(">", ast.op)
            assert.are.equal(100, ast.value)
        end)

        it("parses greater or equal", function()
            local ast = filter.parse("views>=100")
            assert.are.equal(">=", ast.op)
        end)

        it("parses less than", function()
            local ast = filter.parse("views<50")
            assert.are.equal("<", ast.op)
        end)

        it("parses less or equal", function()
            local ast = filter.parse("views<=50")
            assert.are.equal("<=", ast.op)
        end)

        it("parses like operator", function()
            local ast = filter.parse("title~'hello'")
            assert.are.equal("~", ast.op)
            assert.are.equal("hello", ast.value)
        end)

        it("parses not like operator", function()
            local ast = filter.parse("title!~'spam'")
            assert.are.equal("!~", ast.op)
        end)

        it("parses double quoted strings", function()
            local ast = filter.parse('title="hello world"')
            assert.are.equal("hello world", ast.value)
        end)

        it("parses boolean true", function()
            local ast = filter.parse("active=true")
            assert.are.equal(true, ast.value)
        end)

        it("parses boolean false", function()
            local ast = filter.parse("active=false")
            assert.are.equal(false, ast.value)
        end)

        it("parses null", function()
            local ast = filter.parse("deleted=null")
            assert.is_nil(ast.value)
        end)

        it("parses negative numbers", function()
            local ast = filter.parse("balance>-100")
            assert.are.equal(-100, ast.value)
        end)

        it("parses decimal numbers", function()
            local ast = filter.parse("price<99.99")
            assert.are.equal(99.99, ast.value)
        end)

        it("parses AND expression", function()
            local ast = filter.parse("status='active' && views>100")
            assert.are.equal("binary", ast.type)
            assert.are.equal("AND", ast.op)
            assert.are.equal("status", ast.left.field)
            assert.are.equal("views", ast.right.field)
        end)

        it("parses OR expression", function()
            local ast = filter.parse("status='active' || status='pending'")
            assert.are.equal("binary", ast.type)
            assert.are.equal("OR", ast.op)
        end)

        it("parses grouped expressions", function()
            local ast = filter.parse("(status='active' || status='pending') && views>100")
            assert.are.equal("binary", ast.type)
            assert.are.equal("AND", ast.op)
            assert.are.equal("binary", ast.left.type)
            assert.are.equal("OR", ast.left.op)
        end)

        it("parses multi-value operators", function()
            local ast = filter.parse("tags?='lua'")
            assert.are.equal("?=", ast.op)
        end)

        it("handles whitespace", function()
            local ast = filter.parse("  status  =  'active'  ")
            assert.are.equal("status", ast.field)
            assert.are.equal("active", ast.value)
        end)

        it("returns error for empty filter", function()
            local ast, err = filter.parse("")
            assert.is_nil(ast)
            assert.is_truthy(err)
        end)

        it("returns error for invalid syntax", function()
            local ast, err = filter.parse("not valid filter")
            assert.is_nil(ast)
            assert.is_truthy(err)
        end)
    end)

    describe("filter validation", function()
        local schema = {
            title = { type = "string" },
            views = { type = "number" },
        }

        it("accepts valid fields", function()
            local ast = filter.parse("title='hello'")
            local err = filter.validate(ast, schema)
            assert.is_nil(err)
        end)

        it("accepts system fields", function()
            local ast = filter.parse("id=1")
            local err = filter.validate(ast, schema)
            assert.is_nil(err)
        end)

        it("accepts created_at field", function()
            local ast = filter.parse("created_at>1000")
            local err = filter.validate(ast, schema)
            assert.is_nil(err)
        end)

        it("rejects unknown fields", function()
            local ast = filter.parse("unknown='value'")
            local err = filter.validate(ast, schema)
            assert.is_truthy(err)
            assert.is_truthy(err:find("unknown field"))
        end)
    end)

    describe("filter to SQL", function()
        it("converts simple equality", function()
            local ast = filter.parse("status='active'")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("status = ?", sql)
            assert.are.equal("active", params[1])
        end)

        it("converts like with auto-wildcards", function()
            local ast = filter.parse("title~'hello'")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("title LIKE ?", sql)
            assert.are.equal("%hello%", params[1])
        end)

        it("preserves user-specified wildcards", function()
            local ast = filter.parse("title~'hello%'")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("hello%", params[1])
        end)

        it("converts AND expression", function()
            local ast = filter.parse("status='active' && views>100")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("(status = ? AND views > ?)", sql)
            assert.are.equal("active", params[1])
            assert.are.equal(100, params[2])
        end)

        it("converts OR expression", function()
            local ast = filter.parse("status='a' || status='b'")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("(status = ? OR status = ?)", sql)
        end)

        it("converts complex nested expression", function()
            local ast = filter.parse("(status='active' || status='pending') && views>100")
            local sql, params = filter.to_sql(ast)
            assert.are.equal("((status = ? OR status = ?) AND views > ?)", sql)
            assert.are.equal(3, #params)
        end)
    end)

    describe("sort parser", function()
        local schema = {
            title = { type = "string" },
            views = { type = "number" },
        }

        it("parses single ascending field", function()
            local parsed = sort.parse("title")
            assert.are.equal(1, #parsed)
            assert.are.equal("title", parsed[1].field)
            assert.are.equal("ASC", parsed[1].dir)
        end)

        it("parses single descending field", function()
            local parsed = sort.parse("-created_at")
            assert.are.equal("created_at", parsed[1].field)
            assert.are.equal("DESC", parsed[1].dir)
        end)

        it("parses multiple fields", function()
            local parsed = sort.parse("-views,title")
            assert.are.equal(2, #parsed)
            assert.are.equal("views", parsed[1].field)
            assert.are.equal("DESC", parsed[1].dir)
            assert.are.equal("title", parsed[2].field)
            assert.are.equal("ASC", parsed[2].dir)
        end)

        it("accepts + prefix for ascending", function()
            local parsed = sort.parse("+title")
            assert.are.equal("ASC", parsed[1].dir)
        end)

        it("returns nil for empty string", function()
            local parsed = sort.parse("")
            assert.is_nil(parsed)
        end)

        it("returns error for unknown field", function()
            local parsed, err = sort.parse("unknown", schema)
            assert.is_nil(parsed)
            assert.is_truthy(err:find("unknown field"))
        end)

        it("converts to SQL", function()
            local parsed = sort.parse("-views,title", schema)
            local sql = sort.to_sql(parsed)
            assert.are.equal("views DESC, title ASC", sql)
        end)
    end)

    describe("query parser", function()
        local schema = {
            title = { type = "string" },
            status = { type = "string" },
            views = { type = "number" },
        }

        it("parses page parameter", function()
            local opts = query.parse("page=3")
            assert.are.equal(3, opts.page)
        end)

        it("defaults page to 1", function()
            local opts = query.parse("")
            assert.are.equal(1, opts.page)
        end)

        it("parses perPage parameter", function()
            local opts = query.parse("perPage=50")
            assert.are.equal(50, opts.per_page)
        end)

        it("limits perPage to max", function()
            local opts = query.parse("perPage=1000")
            assert.are.equal(500, opts.per_page)
        end)

        it("parses skipTotal parameter", function()
            local opts = query.parse("skipTotal=true")
            assert.is_true(opts.skip_total)
        end)

        it("parses fields parameter", function()
            local opts = query.parse("fields=id,title,status", schema)
            assert.are.equal(3, #opts.fields)
            assert.are.equal("id", opts.fields[1])
            assert.are.equal("title", opts.fields[2])
        end)

        it("filters out invalid fields", function()
            local opts = query.parse("fields=id,unknown,title", schema)
            assert.are.equal(2, #opts.fields)
        end)

        it("parses sort parameter", function()
            local opts = query.parse("sort=-views,title", schema)
            assert.are.equal(2, #opts.sort)
        end)

        it("parses filter parameter", function()
            local opts = query.parse("filter=status='active'", schema)
            assert.is_truthy(opts.filter)
            assert.are.equal("status", opts.filter.field)
        end)

        it("URL decodes parameters", function()
            local opts = query.parse("filter=title%3D%27hello%27")
            assert.is_truthy(opts.filter)
        end)
    end)

    describe("query SQL builder", function()
        local schema = {
            title = { type = "string" },
            status = { type = "string" },
        }

        it("builds basic query", function()
            local built = query.build_sql("posts", { page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("SELECT %* FROM posts"))
            assert.is_truthy(built.sql:find("LIMIT %? OFFSET %?"))
        end)

        it("builds query with fields", function()
            local built = query.build_sql("posts", { fields = { "id", "title" }, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("SELECT id, title FROM posts"))
        end)

        it("builds query with sort", function()
            local sorted = sort.parse("-created_at")
            local built = query.build_sql("posts", { sort = sorted, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("ORDER BY created_at DESC"))
        end)

        it("builds query with filter", function()
            local ast = filter.parse("status='active'")
            local built = query.build_sql("posts", { filter = ast, page = 1, per_page = 20 })
            assert.is_truthy(built.sql:find("WHERE status = %?"))
            assert.are.equal("active", built.params[1])
        end)

        it("builds count query", function()
            local built = query.build_sql("posts", { page = 1, per_page = 20 })
            assert.is_truthy(built.count_sql)
            assert.is_truthy(built.count_sql:find("SELECT COUNT"))
        end)

        it("skips count query when requested", function()
            local built = query.build_sql("posts", { page = 1, per_page = 20, skip_total = true })
            assert.is_nil(built.count_sql)
        end)
    end)
end)
