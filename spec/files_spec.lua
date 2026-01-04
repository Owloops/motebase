local lfs = require("lfs")
local files = require("motebase.files")

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
        it("detects common mime types", function()
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
            assert.are.equal("image/png", files.detect_mime_type("PHOTO.PNG"))
            assert.are.equal("application/octet-stream", files.detect_mime_type("file.xyz"))
            assert.are.equal("application/octet-stream", files.detect_mime_type("noextension"))
        end)
    end)

    describe("filename handling", function()
        it("sanitizes filenames", function()
            assert.are.equal("document.pdf", files.sanitize_filename("document.pdf"))
            assert.are.equal("my-file_v2.txt", files.sanitize_filename("my-file_v2.txt"))
            assert.are.equal("name.txt", files.sanitize_filename("file/name.txt"))
            assert.are.equal("name.txt", files.sanitize_filename("file\\name.txt"))
            assert.are.equal("file_name.txt", files.sanitize_filename("file:name.txt"))
            assert.are.equal("hello_world.pdf", files.sanitize_filename("hello world.pdf"))
            assert.are.equal("file.txt", files.sanitize_filename("../../../file.txt"))
            assert.are.equal("_htaccess", files.sanitize_filename(".htaccess"))
        end)

        it("generates unique filenames", function()
            local name1 = files.generate_filename("test.pdf")
            local name2 = files.generate_filename("test.pdf")

            assert.is_truthy(name1:match("^test_[a-f0-9]+%.pdf$"))
            assert.is_truthy(name2:match("^test_[a-f0-9]+%.pdf$"))
            assert.are_not.equal(name1, name2)

            local name3 = files.generate_filename("README")
            assert.is_truthy(name3:match("^README_[a-f0-9]+$"))
        end)
    end)

    describe("file operations", function()
        it("saves, reads, and deletes files", function()
            local file_info, err = files.save("posts", 1, "test.txt", "Hello World", "text/plain")
            assert.is_nil(err)
            assert.is_truthy(file_info)
            assert.are.equal("test.txt", file_info.filename)
            assert.are.equal(11, file_info.size)
            assert.are.equal("text/plain", file_info.mime_type)

            local data = files.read("posts", 1, "test.txt")
            assert.are.equal("Hello World", data)

            local ok = files.delete("posts", 1, "test.txt")
            assert.is_true(ok)
            assert.is_nil(files.read("posts", 1, "test.txt"))
        end)

        it("deletes all record files", function()
            files.save("posts", 1, "file1.txt", "content1", "text/plain")
            files.save("posts", 1, "file2.txt", "content2", "text/plain")

            local ok = files.delete_record_files("posts", 1)
            assert.is_true(ok)

            assert.is_nil(files.read("posts", 1, "file1.txt"))
            assert.is_nil(files.read("posts", 1, "file2.txt"))
        end)

        it("rejects files exceeding max size", function()
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
        it("serializes and deserializes file info", function()
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

        it("creates and verifies token", function()
            local token, expires = files.create_token()
            assert.is_truthy(token)
            assert.are.equal(120, expires)

            local payload = files.verify_token(token)
            assert.is_truthy(payload)
            assert.are.equal("file", payload.purpose)
            assert.is_truthy(payload.exp)
            assert.is_truthy(payload.jti)
        end)

        it("rejects invalid and tampered tokens", function()
            local payload, err = files.verify_token("invalid.token")
            assert.is_nil(payload)
            assert.are.equal("invalid signature", err)

            local token = files.create_token()
            local tampered = token:gsub(".$", "X")
            local payload2, err2 = files.verify_token(tampered)
            assert.is_nil(payload2)
            assert.are.equal("invalid signature", err2)
        end)

        it("rejects expired token", function()
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

        it("requires secret to create token", function()
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
