rockspec_format = "3.0"
package = "motebase"
version = "scm-1"

source = {
    url = "git+https://github.com/owloops/motebase.git",
}

description = {
    summary = "Tiny self-hosted PocketBase alternative",
    detailed = "MoteBase is a tiny self-hosted PocketBase alternative with dynamic collections, JWT authentication, and SQLite storage.",
    homepage = "https://github.com/owloops/motebase",
    license = "MIT",
}

dependencies = {
    "lua >= 5.1, < 5.5",
    "luasocket >= 3.0",
    "lsqlite3complete >= 0.9",
    "lua-cjson >= 2.1",
    "luafilesystem >= 1.8",
    "lpeg >= 1.0",
}

test_dependencies = {
    "busted",
}

build = {
    type = "builtin",
    modules = {
        ["motebase"] = "motebase/init.lua",
        ["motebase.auth"] = "motebase/auth.lua",
        ["motebase.collections"] = "motebase/collections.lua",
        ["motebase.db"] = "motebase/db.lua",
        ["motebase.files"] = "motebase/files.lua",
        ["motebase.jwt"] = "motebase/jwt.lua",
        ["motebase.middleware"] = "motebase/middleware.lua",
        ["motebase.parser"] = "motebase/parser/init.lua",
        ["motebase.parser.abnf"] = "motebase/parser/abnf.lua",
        ["motebase.parser.email"] = "motebase/parser/email.lua",
        ["motebase.parser.http"] = "motebase/parser/http.lua",
        ["motebase.parser.ih"] = "motebase/parser/ih.lua",
        ["motebase.parser.ip"] = "motebase/parser/ip.lua",
        ["motebase.parser.mime"] = "motebase/parser/mime.lua",
        ["motebase.parser.multipart"] = "motebase/parser/multipart.lua",
        ["motebase.parser.url"] = "motebase/parser/url.lua",
        ["motebase.router"] = "motebase/router.lua",
        ["motebase.schema"] = "motebase/schema.lua",
        ["motebase.server"] = "motebase/server.lua",
        ["motebase.storage"] = "motebase/storage/init.lua",
        ["motebase.storage.local"] = "motebase/storage/local.lua",
        ["motebase.crypto"] = "motebase/crypto/init.lua",
        ["motebase.crypto.bit"] = "motebase/crypto/bit.lua",
        ["motebase.crypto.hmac"] = "motebase/crypto/hmac.lua",
        ["motebase.crypto.sha256"] = "motebase/crypto/sha256.lua",
        ["motebase.utils.log"] = "motebase/utils/log.lua",
        ["motebase.utils.output"] = "motebase/utils/output.lua",
        ["motebase.query"] = "motebase/query/init.lua",
        ["motebase.query.filter"] = "motebase/query/filter.lua",
        ["motebase.query.sort"] = "motebase/query/sort.lua",
    },
    install = {
        bin = {
            ["motebase"] = "bin/motebase.lua",
        },
    },
}
