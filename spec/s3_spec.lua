local s3 = require("motebase.s3")
local crypto = require("motebase.crypto")

describe("s3", function()
    describe("signature", function()
        it("generates correct sha256 hex", function()
            local result = crypto.to_hex(crypto.sha256(""))
            assert.are.equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", result)
        end)

        it("generates correct hmac-sha256", function()
            local result = crypto.to_hex(crypto.hmac_sha256("key", "message"))
            assert.are.equal("6e9ef29b75fffc5b7abae527d58fdadb2fe42e7219011976917343065f58ed4a", result)
        end)
    end)

    describe("configuration", function()
        it("configures with defaults", function()
            s3.configure({
                bucket = "test-bucket",
                access_key = "AKIAIOSFODNN7EXAMPLE",
                secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            })
        end)

        it("auto-detects endpoint from region", function()
            s3.configure({
                bucket = "test-bucket",
                region = "eu-west-1",
                access_key = "AKIAIOSFODNN7EXAMPLE",
                secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            })
        end)

        it("allows custom endpoint for minio", function()
            s3.configure({
                bucket = "test-bucket",
                endpoint = "minio.local:9000",
                path_style = true,
                use_ssl = false,
                access_key = "minioadmin",
                secret_key = "minioadmin",
            })
        end)
    end)

    describe("validation", function()
        before_each(function()
            s3.reset()
        end)

        it("returns error when bucket not configured", function()
            local ok, err = s3.put("test.txt", "content")
            assert.is_nil(ok)
            assert.are.equal("bucket not configured", err)
        end)

        it("returns error when access_key not configured", function()
            s3.configure({ bucket = "test" })
            local ok, err = s3.put("test.txt", "content")
            assert.is_nil(ok)
            assert.are.equal("access_key not configured", err)
        end)

        it("returns error when secret_key not configured", function()
            s3.configure({ bucket = "test", access_key = "key" })
            local ok, err = s3.put("test.txt", "content")
            assert.is_nil(ok)
            assert.are.equal("secret_key not configured", err)
        end)
    end)
end)

describe("s3 storage backend", function()
    local s3_storage = require("motebase.storage.s3")

    it("creates backend with configuration", function()
        local backend = s3_storage.create({
            s3_bucket = "test-bucket",
            s3_region = "us-east-1",
            s3_access_key = "AKIAIOSFODNN7EXAMPLE",
            s3_secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        })

        assert.is_not_nil(backend)
        assert.is_function(backend.init)
        assert.is_function(backend.write)
        assert.is_function(backend.read)
        assert.is_function(backend.delete)
        assert.is_function(backend.exists)
        assert.is_function(backend.mkdir)
        assert.is_function(backend.delete_dir)
    end)

    it("mkdir is a no-op that returns true", function()
        local backend = s3_storage.create({
            s3_bucket = "test-bucket",
            s3_access_key = "key",
            s3_secret_key = "secret",
        })

        local ok = backend.mkdir("some/path")
        assert.is_true(ok)
    end)
end)
