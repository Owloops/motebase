local db = require("motebase.db")
local auth = require("motebase.auth")

describe("auth", function()
    local secret = "test-secret"

    before_each(function()
        db.open(":memory:")
        auth.init()
    end)

    after_each(function()
        db.close()
    end)

    it("registers user", function()
        local user = auth.register("test@example.com", "password123")
        assert.is_truthy(user)
        assert.are.equal(1, user.id)
        assert.are.equal("test@example.com", user.email)
    end)

    it("rejects invalid registration", function()
        local user, err = auth.register("test@example.com", "short")
        assert.is_nil(user)
        assert.are.equal("password must be at least 8 characters", err)

        local user2, err2 = auth.register("invalid", "password123")
        assert.is_nil(user2)
        assert.are.equal("invalid email format", err2)

        auth.register("test@example.com", "password123")
        local user3, err3 = auth.register("test@example.com", "password456")
        assert.is_nil(user3)
        assert.are.equal("email already registered", err3)
    end)

    it("logs in with correct credentials", function()
        auth.register("test@example.com", "password123")
        local result = auth.login("test@example.com", "password123", secret)
        assert.is_truthy(result)
        assert.is_truthy(result.token)
        assert.are.equal("test@example.com", result.user.email)
    end)

    it("rejects invalid login", function()
        auth.register("test@example.com", "password123")

        local result, err = auth.login("test@example.com", "wrongpassword", secret)
        assert.is_nil(result)
        assert.are.equal("invalid credentials", err)

        local result2, err2 = auth.login("noone@example.com", "password123", secret)
        assert.is_nil(result2)
        assert.are.equal("invalid credentials", err2)
    end)

    it("gets user by id", function()
        auth.register("test@example.com", "password123")

        local user = auth.get_user(1)
        assert.is_truthy(user)
        assert.are.equal("test@example.com", user.email)

        assert.is_nil(auth.get_user(999))
    end)
end)
