package.path = package.path .. ";?.lua;?/init.lua"

local lfs = require("lfs")
local db = require("motebase.db")
local schema = require("motebase.schema")
local jwt = require("motebase.jwt")
local router = require("motebase.router")
local collections = require("motebase.collections")
local auth = require("motebase.auth")
local multipart = require("motebase.parser.multipart")
local files = require("motebase.files")
local storage = require("motebase.storage")

local function rmdir_recursive(path)
    local attr = lfs.attributes(path)
    if not attr then return true end

    if attr.mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then rmdir_recursive(path .. "/" .. entry) end
        end
        lfs.rmdir(path)
    else
        os.remove(path)
    end
    return true
end

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
            router.get("/health", function()
                called = true
            end)

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
            router.get("/resource", function()
                return "get"
            end)
            router.post("/resource", function()
                return "post"
            end)

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

                local result = collections.list_records("posts")
                assert.are.equal(2, #result.items)
                assert.are.equal(2, result.totalItems)
                assert.are.equal(1, result.page)
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

    describe("multipart", function()
        it("should detect multipart content type", function()
            assert.is_true(multipart.is_multipart("multipart/form-data; boundary=----WebKitFormBoundary"))
            assert.is_falsy(multipart.is_multipart("application/json"))
            assert.is_falsy(multipart.is_multipart(nil))
        end)

        it("should extract boundary from content type", function()
            local boundary = multipart.get_boundary("multipart/form-data; boundary=----WebKitFormBoundary")
            assert.are.equal("----WebKitFormBoundary", boundary)
        end)

        it("should parse simple form field", function()
            local boundary = "----TestBoundary"
            local body = "------TestBoundary\r\n"
                .. 'Content-Disposition: form-data; name="title"\r\n'
                .. "\r\n"
                .. "Hello World\r\n"
                .. "------TestBoundary--\r\n"

            local parts = multipart.parse(body, boundary)
            assert.is_truthy(parts)
            assert.is_truthy(parts.title)
            assert.are.equal("Hello World", parts.title.data)
        end)

        it("should parse file upload", function()
            local boundary = "----TestBoundary"
            local body = "------TestBoundary\r\n"
                .. 'Content-Disposition: form-data; name="document"; filename="test.txt"\r\n'
                .. "Content-Type: text/plain\r\n"
                .. "\r\n"
                .. "file content here\r\n"
                .. "------TestBoundary--\r\n"

            local parts = multipart.parse(body, boundary)
            assert.is_truthy(parts)
            assert.is_truthy(parts.document)
            assert.are.equal("test.txt", parts.document.filename)
            assert.are.equal("text/plain", parts.document.content_type)
            assert.are.equal("file content here", parts.document.data)
            assert.is_true(multipart.is_file(parts.document))
        end)

        it("should parse mixed fields and files", function()
            local boundary = "----TestBoundary"
            local body = "------TestBoundary\r\n"
                .. 'Content-Disposition: form-data; name="title"\r\n'
                .. "\r\n"
                .. "My Document\r\n"
                .. "------TestBoundary\r\n"
                .. 'Content-Disposition: form-data; name="file"; filename="doc.pdf"\r\n'
                .. "Content-Type: application/pdf\r\n"
                .. "\r\n"
                .. "PDF CONTENT\r\n"
                .. "------TestBoundary--\r\n"

            local parts = multipart.parse(body, boundary)
            assert.is_truthy(parts.title)
            assert.is_truthy(parts.file)
            assert.are.equal("My Document", parts.title.data)
            assert.are.equal("doc.pdf", parts.file.filename)
            assert.is_falsy(multipart.is_file(parts.title))
            assert.is_true(multipart.is_file(parts.file))
        end)

        it("should identify file parts", function()
            local file_part = { name = "doc", filename = "test.pdf", data = "content" }
            local field_part = { name = "title", data = "Hello" }

            assert.is_true(multipart.is_file(file_part))
            assert.is_falsy(multipart.is_file(field_part))
            assert.is_falsy(multipart.is_file(nil))
        end)
    end)

    describe("files", function()
        before_each(function()
            files.configure({
                storage_path = "/tmp/motebase_test_storage",
                max_file_size = 1024 * 1024,
            })
            files.init()
        end)

        after_each(function()
            rmdir_recursive("/tmp/motebase_test_storage")
        end)

        describe("mime detection", function()
            it("should detect common mime types", function()
                assert.are.equal("image/png", files.detect_mime_type("photo.png"))
                assert.are.equal("image/jpeg", files.detect_mime_type("photo.jpg"))
                assert.are.equal("image/jpeg", files.detect_mime_type("photo.jpeg"))
                assert.are.equal("image/gif", files.detect_mime_type("animation.gif"))
                assert.are.equal("application/pdf", files.detect_mime_type("document.pdf"))
                assert.are.equal("text/plain", files.detect_mime_type("readme.txt"))
                assert.are.equal("text/html", files.detect_mime_type("page.html"))
                assert.are.equal("text/css", files.detect_mime_type("styles.css"))
                assert.are.equal("application/javascript", files.detect_mime_type("app.js"))
                assert.are.equal("application/json", files.detect_mime_type("data.json"))
            end)

            it("should handle case insensitive extensions", function()
                assert.are.equal("image/png", files.detect_mime_type("PHOTO.PNG"))
                assert.are.equal("application/pdf", files.detect_mime_type("Doc.PDF"))
            end)

            it("should return octet-stream for unknown types", function()
                assert.are.equal("application/octet-stream", files.detect_mime_type("file.xyz"))
                assert.are.equal("application/octet-stream", files.detect_mime_type("noextension"))
            end)
        end)

        describe("filename sanitization", function()
            it("should keep valid filenames", function()
                assert.are.equal("document.pdf", files.sanitize_filename("document.pdf"))
                assert.are.equal("my-file_v2.txt", files.sanitize_filename("my-file_v2.txt"))
            end)

            it("should extract filename from path", function()
                assert.are.equal("name.txt", files.sanitize_filename("file/name.txt"))
                assert.are.equal("name.txt", files.sanitize_filename("file\\name.txt"))
            end)

            it("should replace special characters with underscore", function()
                assert.are.equal("file_name.txt", files.sanitize_filename("file:name.txt"))
                assert.are.equal("hello_world.pdf", files.sanitize_filename("hello world.pdf"))
            end)

            it("should handle path traversal attempts", function()
                assert.are.equal("file.txt", files.sanitize_filename("../../../file.txt"))
                assert.are.equal("_...file.txt", files.sanitize_filename("....file.txt"))
            end)

            it("should handle leading dots", function()
                assert.are.equal("_htaccess", files.sanitize_filename(".htaccess"))
                assert.are.equal("_gitignore", files.sanitize_filename(".gitignore"))
            end)
        end)

        describe("filename generation", function()
            it("should add random suffix", function()
                local name1 = files.generate_filename("test.pdf")
                local name2 = files.generate_filename("test.pdf")

                assert.is_truthy(name1:match("^test_[a-f0-9]+%.pdf$"))
                assert.is_truthy(name2:match("^test_[a-f0-9]+%.pdf$"))
                assert.are_not.equal(name1, name2)
            end)

            it("should preserve extension", function()
                local name = files.generate_filename("document.pdf")
                assert.is_truthy(name:match("%.pdf$"))

                local name2 = files.generate_filename("image.PNG")
                assert.is_truthy(name2:match("%.PNG$"))
            end)

            it("should handle files without extension", function()
                local name = files.generate_filename("README")
                assert.is_truthy(name:match("^README_[a-f0-9]+$"))
            end)
        end)

        describe("file operations", function()
            it("should save and read file", function()
                local file_info, err = files.save("posts", 1, "test.txt", "Hello World", "text/plain")
                assert.is_nil(err)
                assert.is_truthy(file_info)
                assert.are.equal("test.txt", file_info.filename)
                assert.are.equal(11, file_info.size)
                assert.are.equal("text/plain", file_info.mime_type)

                local data = files.read("posts", 1, "test.txt")
                assert.are.equal("Hello World", data)
            end)

            it("should delete file", function()
                files.save("posts", 1, "test.txt", "content", "text/plain")
                local ok = files.delete("posts", 1, "test.txt")
                assert.is_true(ok)

                local data = files.read("posts", 1, "test.txt")
                assert.is_nil(data)
            end)

            it("should delete all record files", function()
                files.save("posts", 1, "file1.txt", "content1", "text/plain")
                files.save("posts", 1, "file2.txt", "content2", "text/plain")

                local ok = files.delete_record_files("posts", 1)
                assert.is_true(ok)

                assert.is_nil(files.read("posts", 1, "file1.txt"))
                assert.is_nil(files.read("posts", 1, "file2.txt"))
            end)

            it("should reject files exceeding max size", function()
                files.configure({
                    storage_path = "/tmp/motebase_test_storage",
                    max_file_size = 10,
                })

                local file_info, err = files.save("posts", 1, "big.txt", "this is way too long", "text/plain")
                assert.is_nil(file_info)
                assert.is_truthy(err:match("^file too large"))
            end)
        end)

        describe("serialization", function()
            it("should serialize and deserialize file info", function()
                local info = {
                    filename = "doc.pdf",
                    size = 1024,
                    mime_type = "application/pdf",
                }

                local serialized = files.serialize(info)
                assert.is_string(serialized)

                local deserialized = files.deserialize(serialized)
                assert.are.equal("doc.pdf", deserialized.filename)
                assert.are.equal(1024, deserialized.size)
                assert.are.equal("application/pdf", deserialized.mime_type)
            end)

            it("should handle nil or empty input", function()
                assert.is_nil(files.deserialize(nil))
                assert.are.equal("", files.deserialize(""))
            end)
        end)

        describe("file tokens", function()
            before_each(function()
                files.configure({
                    storage_path = "/tmp/motebase_test_storage",
                    secret = "test-secret-key",
                    file_token_duration = 120,
                })
            end)

            it("should create and verify token", function()
                local token, expires = files.create_token()
                assert.is_truthy(token)
                assert.are.equal(120, expires)

                local payload = files.verify_token(token)
                assert.is_truthy(payload)
                assert.are.equal("file", payload.purpose)
                assert.is_truthy(payload.exp)
                assert.is_truthy(payload.jti)
            end)

            it("should reject invalid token", function()
                local payload, err = files.verify_token("invalid.token")
                assert.is_nil(payload)
                assert.are.equal("invalid signature", err)
            end)

            it("should reject tampered token", function()
                local token = files.create_token()
                local tampered = token:gsub(".$", "X")

                local payload, err = files.verify_token(tampered)
                assert.is_nil(payload)
                assert.are.equal("invalid signature", err)
            end)

            it("should reject expired token", function()
                files.configure({
                    storage_path = "/tmp/motebase_test_storage",
                    secret = "test-secret-key",
                    file_token_duration = -1,
                })

                local token = files.create_token()
                local payload, err = files.verify_token(token)
                assert.is_nil(payload)
                assert.are.equal("token expired", err)
            end)

            it("should require secret to create token", function()
                files.configure({
                    storage_path = "/tmp/motebase_test_storage",
                    secret = false,
                })

                local token, err = files.create_token()
                assert.is_nil(token)
                assert.are.equal("secret not configured", err)
            end)
        end)
    end)

    describe("storage", function()
        local test_path = "/tmp/motebase_storage_test"

        before_each(function()
            storage.init({ storage_path = test_path })
        end)

        after_each(function()
            rmdir_recursive(test_path)
        end)

        it("should write and read files", function()
            local ok = storage.write("test/file.txt", "hello storage")
            assert.is_true(ok)

            local data = storage.read("test/file.txt")
            assert.are.equal("hello storage", data)
        end)

        it("should check file existence", function()
            storage.write("exists.txt", "content")

            assert.is_true(storage.exists("exists.txt"))
            assert.is_false(storage.exists("missing.txt"))
        end)

        it("should delete files", function()
            storage.write("todelete.txt", "content")
            assert.is_true(storage.exists("todelete.txt"))

            local ok = storage.delete("todelete.txt")
            assert.is_true(ok)
            assert.is_false(storage.exists("todelete.txt"))
        end)

        it("should create directories", function()
            local ok = storage.mkdir("nested/deep/path")
            assert.is_true(ok)

            storage.write("nested/deep/path/file.txt", "deep content")
            local data = storage.read("nested/deep/path/file.txt")
            assert.are.equal("deep content", data)
        end)

        it("should delete directories", function()
            storage.mkdir("toremove/subdir")
            storage.write("toremove/subdir/file.txt", "content")

            local ok = storage.delete_dir("toremove")
            assert.is_true(ok)
            assert.is_false(storage.exists("toremove/subdir/file.txt"))
        end)

        it("should prevent path traversal", function()
            local data = storage.read("../../../etc/passwd")
            assert.is_nil(data)
        end)

        it("should strip double dots from paths", function()
            storage.write("safe.txt", "safe content")

            local data = storage.read("....safe.txt")
            assert.are.equal("safe content", data)

            local data2 = storage.read("..safe.txt")
            assert.are.equal("safe content", data2)
        end)
    end)
end)
