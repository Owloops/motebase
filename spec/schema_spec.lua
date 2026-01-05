local schema = require("motebase.schema")

describe("schema", function()
    describe("validate_field", function()
        it("validates and coerces primitive types", function()
            assert.are.equal("hello", schema.validate_field("hello", "string", false))
            assert.are.equal(42, schema.validate_field(42, "number", false))
            assert.are.equal(42, schema.validate_field("42", "number", false))
            assert.is_true(schema.validate_field(true, "boolean", false))
            assert.is_false(schema.validate_field(false, "boolean", false))
            assert.is_true(schema.validate_field("true", "boolean", false))
            assert.is_false(schema.validate_field("false", "boolean", false))
        end)

        it("rejects invalid types", function()
            local val, err = schema.validate_field(123, "string", false)
            assert.is_nil(val)
            assert.are.equal("expected string", err)
        end)

        it("validates email format", function()
            local val = schema.validate_field("test@example.com", "email", false)
            assert.are.equal("test@example.com", val)

            local val2, err = schema.validate_field("not-an-email", "email", false)
            assert.is_nil(val2)
            assert.are.equal("invalid email format", err)
        end)

        it("handles required fields", function()
            local val, err = schema.validate_field(nil, "string", true)
            assert.is_nil(val)
            assert.are.equal("field is required", err)

            local val2, err2 = schema.validate_field(nil, "string", false)
            assert.is_nil(val2)
            assert.is_nil(err2)
        end)
    end)

    describe("validate", function()
        it("validates all fields and returns errors", function()
            local fields = {
                name = { type = "string", required = true },
                age = { type = "number" },
            }
            local data = { name = "alice", age = 30 }
            local validated = schema.validate(data, fields)
            assert.are.equal("alice", validated.name)
            assert.are.equal(30, validated.age)

            local fields2 = {
                name = { type = "string", required = true },
                email = { type = "email", required = true },
            }
            local data2 = { email = "invalid" }
            local validated2, errors = schema.validate(data2, fields2)
            assert.is_nil(validated2)
            assert.are.equal("field is required", errors.name)
            assert.are.equal("invalid email format", errors.email)
        end)
    end)

    describe("field_to_sql_type", function()
        it("maps types to SQL", function()
            assert.are.equal("TEXT", schema.field_to_sql_type("string"))
            assert.are.equal("TEXT", schema.field_to_sql_type("email"))
            assert.are.equal("REAL", schema.field_to_sql_type("number"))
            assert.are.equal("INTEGER", schema.field_to_sql_type("boolean"))
            assert.are.equal("TEXT", schema.field_to_sql_type("relation"))
            assert.are.equal("TEXT", schema.field_to_sql_type("unknown"))
        end)
    end)

    describe("relation field", function()
        it("validates single relation", function()
            local field_def = { type = "relation", collection = "users" }
            local val = schema.validate_field(1, "relation", false, field_def)
            assert.are.equal("1", val)

            val = schema.validate_field("42", "relation", false, field_def)
            assert.are.equal("42", val)
        end)

        it("validates multiple relation", function()
            local field_def = { type = "relation", collection = "tags", multiple = true }
            local val = schema.validate_field({ 1, 2, 3 }, "relation", false, field_def)
            assert.are.same({ 1, 2, 3 }, val)

            val = schema.validate_field({ "1", "2" }, "relation", false, field_def)
            assert.are.same({ "1", "2" }, val)
        end)

        it("rejects invalid single relation", function()
            local field_def = { type = "relation", collection = "users" }
            local val, err = schema.validate_field({ 1, 2 }, "relation", false, field_def)
            assert.is_nil(val)
            assert.are.equal("expected ID string or number", err)

            val, err = schema.validate_field(true, "relation", false, field_def)
            assert.is_nil(val)
            assert.are.equal("expected ID string or number", err)
        end)

        it("rejects invalid multiple relation", function()
            local field_def = { type = "relation", collection = "tags", multiple = true }
            local val, err = schema.validate_field("not-an-array", "relation", false, field_def)
            assert.is_nil(val)
            assert.are.equal("expected array of IDs", err)

            val, err = schema.validate_field({ 1, true, 3 }, "relation", false, field_def)
            assert.is_nil(val)
            assert.is_truthy(err:find("invalid ID"))
        end)

        it("allows nil for optional relation", function()
            local field_def = { type = "relation", collection = "users" }
            local val, err = schema.validate_field(nil, "relation", false, field_def)
            assert.is_nil(val)
            assert.is_nil(err)
        end)

        it("requires value for required relation", function()
            local field_def = { type = "relation", collection = "users" }
            local val, err = schema.validate_field(nil, "relation", true, field_def)
            assert.is_nil(val)
            assert.are.equal("field is required", err)
        end)
    end)

    describe("is_relation_field", function()
        it("detects relation fields", function()
            assert.is_true(schema.is_relation_field({ type = "relation", collection = "users" }))
            assert.is_falsy(schema.is_relation_field({ type = "string" }))
            assert.is_falsy(schema.is_relation_field(nil))
        end)
    end)
end)
