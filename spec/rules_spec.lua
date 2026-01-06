local db = require("motebase.db")
local auth = require("motebase.auth")
local collections = require("motebase.collections")
local rules = require("motebase.rules")
local ratelimit = require("motebase.ratelimit")

describe("rules", function()
    describe("parser", function()
        it("parses simple field comparisons", function()
            local ast = rules.parse('status = "active"')
            assert.is_truthy(ast)
            assert.are.equal("comparison", ast.type)
            assert.are.equal("field", ast.field.type)
            assert.are.equal("status", ast.field.name)
            assert.are.equal("=", ast.op)
            assert.are.equal("active", ast.value.value)
        end)

        it("parses @request.auth.* identifiers", function()
            local ast = rules.parse('@request.auth.id != ""')
            assert.is_truthy(ast)
            assert.are.equal("comparison", ast.type)
            assert.are.equal("request", ast.field.type)
            assert.same({ "auth", "id" }, ast.field.path)
        end)

        it("parses @request.body.* identifiers", function()
            local ast = rules.parse('@request.body.status = "draft"')
            assert.is_truthy(ast)
            assert.are.equal("request", ast.field.type)
            assert.same({ "body", "status" }, ast.field.path)
        end)

        it("parses @now macro", function()
            local ast = rules.parse("expiry > @now")
            assert.is_truthy(ast)
            assert.are.equal("macro", ast.value.type)
            assert.are.equal("now", ast.value.name)
        end)

        it("parses combined conditions", function()
            local ast = rules.parse('@request.auth.id != "" && status = "active"')
            assert.is_truthy(ast)
            assert.are.equal("binary", ast.type)
            assert.are.equal("AND", ast.op)
        end)

        it("parses OR conditions", function()
            local ast = rules.parse('status = "a" || status = "b"')
            assert.is_truthy(ast)
            assert.are.equal("binary", ast.type)
            assert.are.equal("OR", ast.op)
        end)

        it("parses grouped conditions", function()
            local ast = rules.parse("(a = 1 || b = 2) && c = 3")
            assert.is_truthy(ast)
            assert.are.equal("binary", ast.type)
            assert.are.equal("AND", ast.op)
        end)

        it("parses any-of operator ?=", function()
            local ast = rules.parse("tags ?= @request.auth.id")
            assert.is_truthy(ast)
            assert.are.equal("?=", ast.op)
        end)

        it("validates rule syntax", function()
            assert.is_true(rules.is_valid(""))
            assert.is_true(rules.is_valid(nil))
            assert.is_true(rules.is_valid('status = "active"'))
            assert.is_false(rules.is_valid("invalid syntax @@"))
        end)

        it("parses // comments", function()
            local ast = rules.parse('status = "active" // this is a comment')
            assert.is_truthy(ast)
            assert.are.equal("active", ast.value.value)
        end)

        it("parses multi-line with comments", function()
            local ast = rules.parse([[
                // check auth first
                @request.auth.id != "" &&
                // then check status
                status = "active"
            ]])
            assert.is_truthy(ast)
            assert.are.equal("binary", ast.type)
        end)

        it("parses nested field paths", function()
            local ast = rules.parse('owner.email = "test@example.com"')
            assert.is_truthy(ast)
            assert.are.equal("field_path", ast.field.type)
            assert.same({ "owner", "email" }, ast.field.path)
        end)

        it("parses field with :lower modifier", function()
            local ast = rules.parse('title:lower = "test"')
            assert.is_truthy(ast)
            assert.are.equal("field_path", ast.field.type)
            assert.are.equal("lower", ast.field.modifier)
        end)

        it("parses @request.body with :isset modifier", function()
            local ast = rules.parse("@request.body.role:isset = false")
            assert.is_truthy(ast)
            assert.are.equal("request", ast.field.type)
            assert.are.equal("isset", ast.field.modifier)
        end)

        it("parses @request.body with :changed modifier", function()
            local ast = rules.parse("@request.body.status:changed = false")
            assert.is_truthy(ast)
            assert.are.equal("changed", ast.field.modifier)
        end)

        it("parses field with :length modifier", function()
            local ast = rules.parse("tags:length > 0")
            assert.is_truthy(ast)
            assert.are.equal("length", ast.field.modifier)
        end)

        it("parses field with :each modifier", function()
            local ast = rules.parse('tags:each ~ "valid"')
            assert.is_truthy(ast)
            assert.are.equal("each", ast.field.modifier)
        end)

        it("parses all datetime macros", function()
            local macros = {
                "@now",
                "@second",
                "@minute",
                "@hour",
                "@weekday",
                "@day",
                "@month",
                "@year",
                "@yesterday",
                "@tomorrow",
                "@todayStart",
                "@todayEnd",
                "@monthStart",
                "@monthEnd",
                "@yearStart",
                "@yearEnd",
            }
            for _, macro in ipairs(macros) do
                local ast = rules.parse("expiry > " .. macro)
                assert.is_truthy(ast, "failed to parse " .. macro)
                assert.are.equal("macro", ast.value.type)
            end
        end)

        it("parses @request.query.*", function()
            local ast = rules.parse('@request.query.filter = "active"')
            assert.is_truthy(ast)
            assert.same({ "query", "filter" }, ast.field.path)
        end)

        it("parses @request.headers.*", function()
            local ast = rules.parse('@request.headers.x_api_key != ""')
            assert.is_truthy(ast)
            assert.same({ "headers", "x_api_key" }, ast.field.path)
        end)

        it("parses @request.method", function()
            local ast = rules.parse('@request.method = "GET"')
            assert.is_truthy(ast)
            assert.same({ "method" }, ast.field.path)
        end)

        it("parses @request.context", function()
            local ast = rules.parse('@request.context != "oauth2"')
            assert.is_truthy(ast)
            assert.same({ "context" }, ast.field.path)
        end)

        it("parses all any-of operators", function()
            local ops = { "?=", "?!=", "?>", "?>=", "?<", "?<=", "?~", "?!~" }
            for _, op in ipairs(ops) do
                local ast = rules.parse("tags " .. op .. ' "test"')
                assert.is_truthy(ast, "failed to parse " .. op)
                assert.are.equal(op, ast.op)
            end
        end)
    end)

    describe("evaluator", function()
        it("evaluates auth.id check", function()
            local ast = rules.parse('@request.auth.id != ""')

            local ctx_auth = { auth = { id = "123" } }
            assert.is_true(rules.check(ast, ctx_auth))

            local ctx_no_auth = { auth = { id = "" } }
            assert.is_false(rules.check(ast, ctx_no_auth))
        end)

        it("evaluates record field check", function()
            local ast = rules.parse('status = "active"')

            local ctx_active = { record = { status = "active" } }
            assert.is_true(rules.check(ast, ctx_active))

            local ctx_inactive = { record = { status = "inactive" } }
            assert.is_false(rules.check(ast, ctx_inactive))
        end)

        it("evaluates owner check", function()
            local ast = rules.parse("owner = @request.auth.id")

            local ctx_owner = { auth = { id = "123" }, record = { owner = "123" } }
            assert.is_true(rules.check(ast, ctx_owner))

            local ctx_not_owner = { auth = { id = "123" }, record = { owner = "456" } }
            assert.is_false(rules.check(ast, ctx_not_owner))
        end)

        it("evaluates AND conditions", function()
            local ast = rules.parse('@request.auth.id != "" && status = "active"')

            local ctx_both = { auth = { id = "1" }, record = { status = "active" } }
            assert.is_true(rules.check(ast, ctx_both))

            local ctx_no_auth = { auth = { id = "" }, record = { status = "active" } }
            assert.is_false(rules.check(ast, ctx_no_auth))

            local ctx_wrong_status = { auth = { id = "1" }, record = { status = "inactive" } }
            assert.is_false(rules.check(ast, ctx_wrong_status))
        end)

        it("evaluates OR conditions", function()
            local ast = rules.parse('role = "admin" || role = "editor"')

            local ctx_admin = { record = { role = "admin" } }
            assert.is_true(rules.check(ast, ctx_admin))

            local ctx_editor = { record = { role = "editor" } }
            assert.is_true(rules.check(ast, ctx_editor))

            local ctx_user = { record = { role = "user" } }
            assert.is_false(rules.check(ast, ctx_user))
        end)

        it("evaluates @now macro", function()
            local ast = rules.parse("expiry > @now")

            local ctx_future = { record = { expiry = "2099-01-01 00:00:00" } }
            assert.is_true(rules.check(ast, ctx_future))

            local ctx_past = { record = { expiry = "2000-01-01 00:00:00" } }
            assert.is_false(rules.check(ast, ctx_past))
        end)

        it("generates SQL filter for record fields", function()
            local ast = rules.parse('status = "published" && views > 100')
            local sql, params = rules.to_sql_filter(ast, {})

            assert.is_truthy(sql)
            assert.is_truthy(sql:find("status"))
            assert.is_truthy(sql:find("views"))
            assert.are.equal(2, #params)
            assert.are.equal("published", params[1])
            assert.are.equal(100, params[2])
        end)

        it("generates partial SQL for mixed rules", function()
            local ast = rules.parse('@request.auth.id != "" && status = "active"')
            local sql, params = rules.to_sql_filter(ast, { auth = { id = "123" } })

            assert.is_truthy(sql)
            assert.is_truthy(sql:find("status"))
            assert.is_falsy(sql:find("auth"))
            assert.are.equal(1, #params)
        end)

        it("evaluates :isset modifier", function()
            local ast = rules.parse("@request.body.role:isset = false")

            local ctx_no_role = { body = {} }
            assert.is_true(rules.check(ast, ctx_no_role))

            local ctx_with_role = { body = { role = "admin" } }
            assert.is_false(rules.check(ast, ctx_with_role))
        end)

        it("evaluates :changed modifier", function()
            local ast = rules.parse("@request.body.status:changed = false")

            local ctx_unchanged = {
                body = { status = "active" },
                record = { status = "active" },
            }
            assert.is_true(rules.check(ast, ctx_unchanged))

            local ctx_changed = {
                body = { status = "inactive" },
                record = { status = "active" },
            }
            assert.is_false(rules.check(ast, ctx_changed))
        end)

        it("evaluates :length modifier", function()
            local ast = rules.parse("tags:length > 1")

            local ctx_many = { record = { tags = { "a", "b", "c" } } }
            assert.is_true(rules.check(ast, ctx_many))

            local ctx_one = { record = { tags = { "a" } } }
            assert.is_false(rules.check(ast, ctx_one))
        end)

        it("evaluates :each modifier", function()
            local ast = rules.parse('options:each = "valid"')

            local ctx_all_valid = { record = { options = { "valid", "valid" } } }
            assert.is_true(rules.check(ast, ctx_all_valid))

            local ctx_some_invalid = { record = { options = { "valid", "invalid" } } }
            assert.is_false(rules.check(ast, ctx_some_invalid))
        end)

        it("evaluates :lower modifier", function()
            local ast = rules.parse('title:lower = "test"')

            local ctx_upper = { record = { title = "TEST" } }
            assert.is_true(rules.check(ast, ctx_upper))

            local ctx_mixed = { record = { title = "TeSt" } }
            assert.is_true(rules.check(ast, ctx_mixed))
        end)

        it("evaluates @request.query.*", function()
            local ast = rules.parse('@request.query.status = "active"')

            local ctx_match = { query = { status = "active" } }
            assert.is_true(rules.check(ast, ctx_match))

            local ctx_no_match = { query = { status = "inactive" } }
            assert.is_false(rules.check(ast, ctx_no_match))
        end)

        it("evaluates @request.headers.*", function()
            local ast = rules.parse('@request.headers.x_api_key != ""')

            local ctx_with_key = { headers = { x_api_key = "secret123" } }
            assert.is_true(rules.check(ast, ctx_with_key))

            local ctx_no_key = { headers = {} }
            assert.is_false(rules.check(ast, ctx_no_key))
        end)

        it("evaluates @request.method", function()
            local ast = rules.parse('@request.method = "POST"')

            local ctx_post = { method = "POST" }
            assert.is_true(rules.check(ast, ctx_post))

            local ctx_get = { method = "GET" }
            assert.is_false(rules.check(ast, ctx_get))
        end)

        it("evaluates @request.context", function()
            local ast = rules.parse('@request.context != "oauth2"')

            local ctx_default = { context = "default" }
            assert.is_true(rules.check(ast, ctx_default))

            local ctx_oauth = { context = "oauth2" }
            assert.is_false(rules.check(ast, ctx_oauth))
        end)

        it("evaluates nested field path", function()
            local ast = rules.parse('author.role = "admin"')

            local ctx_admin = { record = { author = { role = "admin" } } }
            assert.is_true(rules.check(ast, ctx_admin))

            local ctx_user = { record = { author = { role = "user" } } }
            assert.is_false(rules.check(ast, ctx_user))
        end)

        it("evaluates datetime macros", function()
            local ast = rules.parse("created_at < @tomorrow")

            local ctx = { record = { created_at = os.date("!%Y-%m-%d %H:%M:%S") } }
            assert.is_true(rules.check(ast, ctx))
        end)

        it("evaluates all any-of operators", function()
            local ctx = { record = { scores = { 10, 20, 30 } } }

            assert.is_true(rules.check(rules.parse("scores ?= 20"), ctx))
            assert.is_true(rules.check(rules.parse("scores ?!= 5"), ctx))
            assert.is_true(rules.check(rules.parse("scores ?> 25"), ctx))
            assert.is_true(rules.check(rules.parse("scores ?>= 30"), ctx))
            assert.is_true(rules.check(rules.parse("scores ?< 15"), ctx))
            assert.is_true(rules.check(rules.parse("scores ?<= 10"), ctx))
        end)

        it("evaluates like operator with wildcards", function()
            local ast = rules.parse('title ~ "Lorem%"')

            local ctx_match = { record = { title = "Lorem ipsum" } }
            assert.is_true(rules.check(ast, ctx_match))

            local ctx_no_match = { record = { title = "Hello world" } }
            assert.is_false(rules.check(ast, ctx_no_match))
        end)
    end)
end)

describe("auth superuser", function()
    before_each(function()
        db.open(":memory:")
        auth.init()
    end)

    after_each(function()
        auth.configure({})
        db.close()
    end)

    it("first user is superuser by default", function()
        auth.register("first@example.com", "password123")

        local user = auth.get_user(1)
        assert.is_true(auth.is_superuser(user))
        assert.is_true(auth.is_superuser({ sub = 1 }))
    end)

    it("configured superuser takes precedence", function()
        auth.configure({ superuser = "admin@example.com" })

        auth.register("first@example.com", "password123")
        auth.register("admin@example.com", "password123")

        local first = auth.get_user(1)
        local admin = auth.get_user(2)

        assert.is_false(auth.is_superuser(first))
        assert.is_true(auth.is_superuser(admin))
    end)

    it("returns false for nil user", function()
        assert.is_false(auth.is_superuser(nil))
    end)
end)

describe("collection rules", function()
    before_each(function()
        db.open(":memory:")
        collections.init()
    end)

    after_each(function()
        db.close()
    end)

    it("creates collection with rules", function()
        local rules_cfg = {
            listRule = "",
            viewRule = "",
            createRule = '@request.auth.id != ""',
            updateRule = "owner = @request.auth.id",
            deleteRule = nil,
        }

        collections.create("posts", { title = { type = "string" } }, rules_cfg)

        local col = collections.get("posts")
        assert.is_truthy(col)
        assert.are.equal("", col.listRule)
        assert.are.equal("", col.viewRule)
        assert.are.equal('@request.auth.id != ""', col.createRule)
        assert.are.equal("owner = @request.auth.id", col.updateRule)
        assert.is_nil(col.deleteRule)
    end)

    it("updates collection rules", function()
        collections.create("posts", { title = { type = "string" } }, { listRule = "" })

        collections.update("posts", { listRule = '@request.auth.id != ""' })

        local col = collections.get("posts")
        assert.are.equal('@request.auth.id != ""', col.listRule)
    end)

    it("lists collections with rules", function()
        collections.create("posts", { title = { type = "string" } }, { listRule = "", viewRule = "" })

        local list = collections.list()
        assert.are.equal(1, #list)
        assert.are.equal("", list[1].listRule)
        assert.are.equal("", list[1].viewRule)
    end)
end)

describe("ratelimit", function()
    before_each(function()
        ratelimit.reset()
        ratelimit.configure({
            ["/api/auth/login"] = { max = 3, window = 60 },
            ["*"] = { max = 5, window = 60 },
        })
    end)

    it("allows requests within limit", function()
        for _ = 1, 3 do
            assert.is_true(ratelimit.check("127.0.0.1", "/api/auth/login"))
        end
    end)

    it("blocks requests over limit", function()
        for _ = 1, 3 do
            ratelimit.check("127.0.0.1", "/api/auth/login")
        end

        assert.is_false(ratelimit.check("127.0.0.1", "/api/auth/login"))
    end)

    it("uses default config for unknown paths", function()
        for _ = 1, 5 do
            assert.is_true(ratelimit.check("127.0.0.1", "/api/some/path"))
        end

        assert.is_false(ratelimit.check("127.0.0.1", "/api/some/path"))
    end)

    it("separates buckets by IP", function()
        for _ = 1, 3 do
            ratelimit.check("127.0.0.1", "/api/auth/login")
        end

        assert.is_false(ratelimit.check("127.0.0.1", "/api/auth/login"))
        assert.is_true(ratelimit.check("192.168.1.1", "/api/auth/login"))
    end)

    it("separates buckets by path", function()
        for _ = 1, 3 do
            ratelimit.check("127.0.0.1", "/api/auth/login")
        end

        assert.is_false(ratelimit.check("127.0.0.1", "/api/auth/login"))
        assert.is_true(ratelimit.check("127.0.0.1", "/api/auth/register"))
    end)
end)
