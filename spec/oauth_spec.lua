local oauth = require("motebase.oauth")

describe("oauth", function()
    describe("providers", function()
        it("lists no providers when none configured", function()
            local providers = oauth.list_providers()
            local cjson = require("cjson")
            -- Empty array is cjson.empty_array userdata or empty table
            assert.is_truthy(providers == cjson.empty_array or (type(providers) == "table" and #providers == 0))
        end)

        it("checks if provider is enabled", function()
            assert.is_false(oauth.is_enabled("google"))
            assert.is_false(oauth.is_enabled("github"))
            assert.is_false(oauth.is_enabled("unknown"))
        end)
    end)

    describe("auth url", function()
        it("rejects unknown provider", function()
            local url, err = oauth.get_auth_url("unknown")
            assert.is_nil(url)
            assert.are.equal("unknown provider", err)
        end)

        it("rejects unconfigured provider", function()
            local url, err = oauth.get_auth_url("google")
            assert.is_nil(url)
            assert.are.equal("provider not configured", err)
        end)
    end)

    describe("code exchange", function()
        it("rejects unknown provider", function()
            local token, err = oauth.exchange_code("unknown", "code", "state")
            assert.is_nil(token)
            assert.are.equal("unknown provider", err)
        end)

        it("rejects invalid state", function()
            local token, err = oauth.exchange_code("google", "code", "invalid-state")
            assert.is_nil(token)
            assert.are.equal("invalid or expired state", err)
        end)
    end)

    describe("user info", function()
        it("rejects unknown provider", function()
            local info, err = oauth.get_user_info("unknown", "token")
            assert.is_nil(info)
            assert.are.equal("unknown provider", err)
        end)
    end)

    describe("configuration", function()
        it("accepts provider credentials", function()
            oauth.configure({
                redirect_url = "http://localhost:8097/api/auth/oauth",
                google_id = "test-google-id",
                google_secret = "test-google-secret",
            })

            assert.is_true(oauth.is_enabled("google"))
            assert.is_false(oauth.is_enabled("github"))

            local providers = oauth.list_providers()
            assert.are.equal(1, #providers)
            assert.are.equal("google", providers[1])

            oauth.configure({
                google_id = nil,
                google_secret = nil,
                redirect_url = nil,
            })
        end)

        it("generates auth url with state", function()
            oauth.configure({
                redirect_url = "http://localhost:8097/api/auth/oauth",
                google_id = "test-google-id",
                google_secret = "test-google-secret",
            })

            local url, state = oauth.get_auth_url("google")
            assert.is_truthy(url)
            assert.is_truthy(state)
            assert.is_truthy(url:find("accounts.google.com"))
            assert.is_truthy(url:find("client_id=test%-google%-id"))
            assert.is_truthy(url:find("state=" .. state))

            oauth.configure({
                google_id = nil,
                google_secret = nil,
                redirect_url = nil,
            })
        end)
    end)
end)
