rockspec_format = "3.0"
package = "motebase"
version = "scm-1"

source = {
    url = "git+https://github.com/pgagnidze/motebase.git",
}

description = {
    summary = "Minimal Backend-as-a-Service for unikernels",
    homepage = "https://github.com/pgagnidze/motebase",
    license = "MIT",
}

dependencies = {
    "lua >= 5.1, < 5.5",
    "luasocket >= 3.0",
    "lsqlite3complete >= 0.9",
    "lua-cjson >= 2.1",
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
        ["motebase.jwt"] = "motebase/jwt.lua",
        ["motebase.middleware"] = "motebase/middleware.lua",
        ["motebase.router"] = "motebase/router.lua",
        ["motebase.schema"] = "motebase/schema.lua",
        ["motebase.server"] = "motebase/server.lua",
        ["motebase.crypto"] = "motebase/crypto/init.lua",
        ["motebase.crypto.bit"] = "motebase/crypto/bit.lua",
        ["motebase.crypto.hmac"] = "motebase/crypto/hmac.lua",
        ["motebase.crypto.sha256"] = "motebase/crypto/sha256.lua",
        ["motebase.utils.log"] = "motebase/utils/log.lua",
        ["motebase.utils.output"] = "motebase/utils/output.lua",
    },
    install = {
        bin = {
            ["motebase"] = "bin/motebase.lua",
        },
    },
}
