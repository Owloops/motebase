local db = require("motebase.db")
local auth = require("motebase.auth")

describe("auth", function()
    local secret = "test-secret"

    before_each(function()
        db.open(":memory:")
        auth.init()
        auth.configure({ superuser = nil })
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

    describe("superuser", function()
        it("treats first user as superuser by default", function()
            auth.register("first@example.com", "password123")
            auth.register("second@example.com", "password123")

            assert.is_true(auth.is_superuser({ id = 1 }))
            assert.is_false(auth.is_superuser({ id = 2 }))
        end)

        it("uses configured superuser email", function()
            auth.configure({ superuser = "admin@example.com" })
            auth.register("first@example.com", "password123")
            auth.register("admin@example.com", "password123")

            assert.is_false(auth.is_superuser({ email = "first@example.com" }))
            assert.is_true(auth.is_superuser({ email = "admin@example.com" }))

            auth.configure({ superuser = nil })
        end)

        it("resolves email from sub claim", function()
            auth.register("test@example.com", "password123")
            assert.is_true(auth.is_superuser({ sub = 1 }))
        end)
    end)

    describe("password reset", function()
        it("returns true even for non-existent email (anti-enumeration)", function()
            local ok = auth.request_password_reset("nobody@example.com")
            assert.is_true(ok)
        end)

        it("creates reset token for existing user", function()
            auth.register("test@example.com", "password123")
            local ok = auth.request_password_reset("test@example.com")
            assert.is_true(ok)

            local users = db.query("SELECT reset_token, reset_token_expiry FROM _users WHERE email = ?", { "test@example.com" })
            assert.is_truthy(users[1].reset_token)
            assert.is_truthy(users[1].reset_token_expiry)
        end)

        it("rejects invalid or expired token", function()
            local ok, err = auth.confirm_password_reset("invalid-token", "newpassword123")
            assert.is_nil(ok)
            assert.are.equal("invalid or expired token", err)
        end)

        it("rejects short password", function()
            local ok, err = auth.confirm_password_reset("sometoken", "short")
            assert.is_nil(ok)
            assert.are.equal("password must be at least 8 characters", err)
        end)
    end)

    describe("email verification", function()
        it("creates verification token", function()
            auth.register("test@example.com", "password123")
            local ok = auth.request_verification(1)
            assert.is_true(ok)

            local users = db.query("SELECT verify_token, verify_token_expiry FROM _users WHERE id = ?", { 1 })
            assert.is_truthy(users[1].verify_token)
            assert.is_truthy(users[1].verify_token_expiry)
        end)

        it("rejects verification for non-existent user", function()
            local ok, err = auth.request_verification(999)
            assert.is_nil(ok)
            assert.are.equal("user not found", err)
        end)

        it("rejects verification for already verified user", function()
            auth.register("test@example.com", "password123")
            db.exec("UPDATE _users SET verified = 1 WHERE id = 1")

            local ok, err = auth.request_verification(1)
            assert.is_nil(ok)
            assert.are.equal("already verified", err)
        end)

        it("rejects invalid verification token", function()
            local ok, err = auth.confirm_verification("invalid-token")
            assert.is_nil(ok)
            assert.are.equal("invalid or expired token", err)
        end)
    end)

    describe("oauth", function()
        it("finds existing user by email", function()
            auth.register("test@example.com", "password123")

            local user = auth.find_or_create_oauth_user("test@example.com", "google", "12345")
            assert.is_truthy(user)
            assert.are.equal(1, user.id)
            assert.are.equal("test@example.com", user.email)
        end)

        it("creates new user if not found", function()
            local user = auth.find_or_create_oauth_user("new@example.com", "github", "67890")
            assert.is_truthy(user)
            assert.are.equal(1, user.id)
            assert.are.equal("new@example.com", user.email)

            local users = db.query("SELECT verified FROM _users WHERE id = ?", { 1 })
            assert.are.equal(1, users[1].verified)
        end)

        it("rejects missing email", function()
            local user, err = auth.find_or_create_oauth_user(nil, "google", "12345")
            assert.is_nil(user)
            assert.are.equal("email required", err)
        end)
    end)
end)
