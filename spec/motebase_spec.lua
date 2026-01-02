package.path = package.path .. ";?.lua;?/init.lua"

local db = require("motebase.db")
local schema = require("motebase.schema")
local jwt = require("motebase.jwt")
local router = require("motebase.router")
local collections = require("motebase.collections")
local auth = require("motebase.auth")

describe("motebase", function()
  describe("db", function()
    before_each(function()
      db.open(":memory:")
    end)

    after_each(function()
      db.close()
    end)

    it("should open and close database", function()
      assert.is_truthy(db.get_connection())
      db.close()
      assert.is_nil(db.get_connection())
    end)

    it("should execute SQL", function()
      local ok = db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
      assert.is_true(ok)
    end)

    it("should return error for invalid SQL", function()
      local ok, err = db.exec("INVALID SQL")
      assert.is_nil(ok)
      assert.is_truthy(err)
    end)

    it("should insert and query rows", function()
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
      local id = db.insert("INSERT INTO test (name) VALUES (?)", { "alice" })
      assert.are.equal(1, id)

      local rows = db.query("SELECT * FROM test WHERE id = ?", { 1 })
      assert.are.equal(1, #rows)
      assert.are.equal("alice", rows[1].name)
    end)

    it("should update rows", function()
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
      db.insert("INSERT INTO test (name) VALUES (?)", { "alice" })

      local changes = db.run("UPDATE test SET name = ? WHERE id = ?", { "bob", 1 })
      assert.are.equal(1, changes)

      local rows = db.query("SELECT * FROM test WHERE id = ?", { 1 })
      assert.are.equal("bob", rows[1].name)
    end)

    it("should delete rows", function()
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
      db.insert("INSERT INTO test (name) VALUES (?)", { "alice" })

      local changes = db.run("DELETE FROM test WHERE id = ?", { 1 })
      assert.are.equal(1, changes)

      local rows = db.query("SELECT * FROM test")
      assert.are.equal(0, #rows)
    end)

    it("should handle boolean binding", function()
      db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, active INTEGER)")
      db.insert("INSERT INTO test (active) VALUES (?)", { true })
      db.insert("INSERT INTO test (active) VALUES (?)", { false })

      local rows = db.query("SELECT * FROM test ORDER BY id")
      assert.are.equal(1, rows[1].active)
      assert.are.equal(0, rows[2].active)
    end)
  end)

  describe("schema", function()
    describe("validate_field", function()
      it("should validate string", function()
        local val = schema.validate_field("hello", "string", false)
        assert.are.equal("hello", val)
      end)

      it("should reject non-string for string type", function()
        local val, err = schema.validate_field(123, "string", false)
        assert.is_nil(val)
        assert.are.equal("expected string", err)
      end)

      it("should validate number", function()
        local val = schema.validate_field(42, "number", false)
        assert.are.equal(42, val)
      end)

      it("should coerce string to number", function()
        local val = schema.validate_field("42", "number", false)
        assert.are.equal(42, val)
      end)

      it("should validate boolean", function()
        assert.is_true(schema.validate_field(true, "boolean", false))
        assert.is_false(schema.validate_field(false, "boolean", false))
      end)

      it("should coerce string to boolean", function()
        assert.is_true(schema.validate_field("true", "boolean", false))
        assert.is_false(schema.validate_field("false", "boolean", false))
      end)

      it("should validate email format", function()
        local val = schema.validate_field("test@example.com", "email", false)
        assert.are.equal("test@example.com", val)
      end)

      it("should reject invalid email", function()
        local val, err = schema.validate_field("not-an-email", "email", false)
        assert.is_nil(val)
        assert.are.equal("invalid email format", err)
      end)

      it("should require field when required is true", function()
        local val, err = schema.validate_field(nil, "string", true)
        assert.is_nil(val)
        assert.are.equal("field is required", err)
      end)

      it("should allow nil when required is false", function()
        local val, err = schema.validate_field(nil, "string", false)
        assert.is_nil(val)
        assert.is_nil(err)
      end)
    end)

    describe("validate", function()
      it("should validate all fields", function()
        local fields = {
          name = { type = "string", required = true },
          age = { type = "number" },
        }
        local data = { name = "alice", age = 30 }
        local validated = schema.validate(data, fields)
        assert.are.equal("alice", validated.name)
        assert.are.equal(30, validated.age)
      end)

      it("should return errors for invalid fields", function()
        local fields = {
          name = { type = "string", required = true },
          email = { type = "email", required = true },
        }
        local data = { email = "invalid" }
        local validated, errors = schema.validate(data, fields)
        assert.is_nil(validated)
        assert.are.equal("field is required", errors.name)
        assert.are.equal("invalid email format", errors.email)
      end)
    end)

    describe("field_to_sql_type", function()
      it("should map types to SQL", function()
        assert.are.equal("TEXT", schema.field_to_sql_type("string"))
        assert.are.equal("TEXT", schema.field_to_sql_type("email"))
        assert.are.equal("REAL", schema.field_to_sql_type("number"))
        assert.are.equal("INTEGER", schema.field_to_sql_type("boolean"))
        assert.are.equal("TEXT", schema.field_to_sql_type("unknown"))
      end)
    end)
  end)

  describe("jwt", function()
    local secret = "test-secret-key"

    it("should encode and decode token", function()
      local payload = { sub = 123, name = "alice" }
      local token = jwt.encode(payload, secret)
      assert.is_string(token)
      assert.is_truthy(token:match("^[%w%-_]+%.[%w%-_]+%.[%w%-_]+$"))

      local decoded = jwt.decode(token, secret)
      assert.are.equal(123, decoded.sub)
      assert.are.equal("alice", decoded.name)
    end)

    it("should reject invalid signature", function()
      local payload = { sub = 123 }
      local token = jwt.encode(payload, secret)

      local decoded, err = jwt.decode(token, "wrong-secret")
      assert.is_nil(decoded)
      assert.are.equal("invalid signature", err)
    end)

    it("should reject expired token", function()
      local payload = { sub = 123, exp = os.time() - 100 }
      local token = jwt.encode(payload, secret)

      local decoded, err = jwt.decode(token, secret)
      assert.is_nil(decoded)
      assert.are.equal("token expired", err)
    end)

    it("should reject invalid token format", function()
      local decoded, err = jwt.decode("not.valid", secret)
      assert.is_nil(decoded)
      assert.are.equal("invalid token format", err)
    end)

    it("should create token with expiry", function()
      local token = jwt.create_token(42, secret, { expires_in = 3600 })
      local decoded = jwt.decode(token, secret)
      assert.are.equal(42, decoded.sub)
      assert.is_truthy(decoded.exp)
      assert.is_truthy(decoded.iat)
      assert.is_truthy(decoded.jti)
      assert.is_true(decoded.exp > os.time())
    end)

    it("should generate unique jti for each token", function()
      local token1 = jwt.create_token(1, secret)
      local token2 = jwt.create_token(1, secret)
      local decoded1 = jwt.decode(token1, secret)
      local decoded2 = jwt.decode(token2, secret)
      assert.are_not.equal(decoded1.jti, decoded2.jti)
    end)

    it("should include audience when specified", function()
      local token = jwt.create_token(1, secret, { audience = "api.example.com" })
      local decoded = jwt.decode(token, secret)
      assert.are.equal("api.example.com", decoded.aud)
    end)

    it("should validate audience when checking", function()
      local token = jwt.create_token(1, secret, { audience = "api.example.com" })

      local decoded = jwt.decode(token, secret, { audience = "api.example.com" })
      assert.are.equal(1, decoded.sub)

      local decoded2, err = jwt.decode(token, secret, { audience = "other.example.com" })
      assert.is_nil(decoded2)
      assert.are.equal("invalid audience", err)
    end)

    it("should include issuer when specified", function()
      local token = jwt.create_token(1, secret, { issuer = "motebase" })
      local decoded = jwt.decode(token, secret)
      assert.are.equal("motebase", decoded.iss)
    end)
  end)

  describe("router", function()
    before_each(function()
      router.clear()
    end)

    it("should match simple routes", function()
      local called = false
      router.get("/health", function() called = true end)

      local handler = router.match("GET", "/health")
      assert.is_truthy(handler)
      handler()
      assert.is_true(called)
    end)

    it("should match routes with params", function()
      router.get("/users/:id", function() end)

      local handler, params = router.match("GET", "/users/123")
      assert.is_truthy(handler)
      assert.are.equal("123", params.id)
    end)

    it("should match routes with multiple params", function()
      router.get("/collections/:name/records/:id", function() end)

      local handler, params = router.match("GET", "/collections/posts/records/42")
      assert.is_truthy(handler)
      assert.are.equal("posts", params.name)
      assert.are.equal("42", params.id)
    end)

    it("should match different methods", function()
      router.get("/resource", function() return "get" end)
      router.post("/resource", function() return "post" end)

      local get_handler = router.match("GET", "/resource")
      local post_handler = router.match("POST", "/resource")
      local delete_handler = router.match("DELETE", "/resource")

      assert.is_truthy(get_handler)
      assert.is_truthy(post_handler)
      assert.is_nil(delete_handler)
    end)

    it("should return nil for unmatched routes", function()
      router.get("/exists", function() end)

      local handler = router.match("GET", "/not-exists")
      assert.is_nil(handler)
    end)
  end)

  describe("collections", function()
    before_each(function()
      db.open(":memory:")
      collections.init()
    end)

    after_each(function()
      db.close()
    end)

    it("should create collection", function()
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

    it("should reject invalid collection name", function()
      local ok, err = collections.create("123invalid", {})
      assert.is_nil(ok)
      assert.are.equal("invalid collection name", err)
    end)

    it("should reject reserved collection name", function()
      local ok, err = collections.create("_private", {})
      assert.is_nil(ok)
      assert.are.equal("collection name cannot start with underscore", err)
    end)

    it("should reject duplicate collection", function()
      collections.create("posts", { title = { type = "string" } })
      local ok, err = collections.create("posts", { title = { type = "string" } })
      assert.is_nil(ok)
      assert.are.equal("collection already exists", err)
    end)

    it("should list collections", function()
      collections.create("posts", { title = { type = "string" } })
      collections.create("users", { name = { type = "string" } })

      local list = collections.list()
      assert.are.equal(2, #list)
    end)

    it("should delete collection", function()
      collections.create("posts", { title = { type = "string" } })
      local ok = collections.delete("posts")
      assert.is_true(ok)

      local collection = collections.get("posts")
      assert.is_nil(collection)
    end)

    describe("records", function()
      before_each(function()
        collections.create("posts", {
          title = { type = "string", required = true },
          views = { type = "number" },
        })
      end)

      it("should create record", function()
        local record = collections.create_record("posts", { title = "Hello", views = 10 })
        assert.is_truthy(record)
        assert.are.equal(1, record.id)
        assert.are.equal("Hello", record.title)
        assert.are.equal(10, record.views)
      end)

      it("should reject record with missing required field", function()
        local record, err = collections.create_record("posts", { views = 10 })
        assert.is_nil(record)
        assert.are.equal("field is required", err.title)
      end)

      it("should list records", function()
        collections.create_record("posts", { title = "Post 1" })
        collections.create_record("posts", { title = "Post 2" })

        local records = collections.list_records("posts")
        assert.are.equal(2, #records)
      end)

      it("should get record by id", function()
        collections.create_record("posts", { title = "Hello" })

        local record = collections.get_record("posts", 1)
        assert.is_truthy(record)
        assert.are.equal("Hello", record.title)
      end)

      it("should update record", function()
        collections.create_record("posts", { title = "Hello" })

        local record = collections.update_record("posts", 1, { title = "Updated" })
        assert.are.equal("Updated", record.title)
      end)

      it("should delete record", function()
        collections.create_record("posts", { title = "Hello" })

        local ok = collections.delete_record("posts", 1)
        assert.is_true(ok)

        local record = collections.get_record("posts", 1)
        assert.is_nil(record)
      end)

      it("should return error for non-existent record", function()
        local record = collections.get_record("posts", 999)
        assert.is_nil(record)
      end)
    end)
  end)

  describe("auth", function()
    local secret = "test-secret"

    before_each(function()
      db.open(":memory:")
      auth.init()
    end)

    after_each(function()
      db.close()
    end)

    it("should register user", function()
      local user = auth.register("test@example.com", "password123")
      assert.is_truthy(user)
      assert.are.equal(1, user.id)
      assert.are.equal("test@example.com", user.email)
    end)

    it("should reject short password", function()
      local user, err = auth.register("test@example.com", "short")
      assert.is_nil(user)
      assert.are.equal("password must be at least 8 characters", err)
    end)

    it("should reject invalid email", function()
      local user, err = auth.register("invalid", "password123")
      assert.is_nil(user)
      assert.are.equal("invalid email format", err)
    end)

    it("should reject duplicate email", function()
      auth.register("test@example.com", "password123")
      local user, err = auth.register("test@example.com", "password456")
      assert.is_nil(user)
      assert.are.equal("email already registered", err)
    end)

    it("should login with correct credentials", function()
      auth.register("test@example.com", "password123")
      local result = auth.login("test@example.com", "password123", secret)
      assert.is_truthy(result)
      assert.is_truthy(result.token)
      assert.are.equal("test@example.com", result.user.email)
    end)

    it("should reject login with wrong password", function()
      auth.register("test@example.com", "password123")
      local result, err = auth.login("test@example.com", "wrongpassword", secret)
      assert.is_nil(result)
      assert.are.equal("invalid credentials", err)
    end)

    it("should reject login with non-existent email", function()
      local result, err = auth.login("noone@example.com", "password123", secret)
      assert.is_nil(result)
      assert.are.equal("invalid credentials", err)
    end)

    it("should get user by id", function()
      auth.register("test@example.com", "password123")
      local user = auth.get_user(1)
      assert.is_truthy(user)
      assert.are.equal("test@example.com", user.email)
    end)

    it("should return nil for non-existent user", function()
      local user = auth.get_user(999)
      assert.is_nil(user)
    end)
  end)
end)
