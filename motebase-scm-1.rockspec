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
    "luasec >= 1.0",
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
        ["motebase.parser.core"] = "motebase/parser/core.lua",
        ["motebase.parser.email"] = "motebase/parser/email.lua",
        ["motebase.parser.http"] = "motebase/parser/http.lua",
        ["motebase.parser.ip"] = "motebase/parser/ip.lua",
        ["motebase.parser.mime"] = "motebase/parser/mime.lua",
        ["motebase.parser.multipart"] = "motebase/parser/multipart.lua",
        ["motebase.parser.uri"] = "motebase/parser/uri.lua",
        ["motebase.router"] = "motebase/router.lua",
        ["motebase.schema"] = "motebase/schema.lua",
        ["motebase.server"] = "motebase/server.lua",
        ["motebase.storage"] = "motebase/storage/init.lua",
        ["motebase.storage.local"] = "motebase/storage/local.lua",
        ["motebase.crypto"] = "motebase/crypto/init.lua",
        ["motebase.crypto.hashings_c"] = {
            sources = {
                "motebase/crypto/hashings.c",
                "motebase/crypto/sha256.c",
                "motebase/crypto/hmac_sha256.c",
            },
            incdirs = { "motebase/crypto" },
        },
        ["motebase.utils.log"] = "motebase/utils/log.lua",
        ["motebase.utils.output"] = "motebase/utils/output.lua",
        ["motebase.utils.url"] = "motebase/utils/url.lua",
        ["motebase.query"] = "motebase/query/init.lua",
        ["motebase.query.expand"] = "motebase/query/expand.lua",
        ["motebase.query.filter"] = "motebase/query/filter.lua",
        ["motebase.query.sort"] = "motebase/query/sort.lua",
        ["motebase.poll"] = "motebase/poll.lua",
        ["motebase.poll_c"] = {
            sources = { "motebase/poll.c" },
        },
        ["motebase.ratelimit"] = "motebase/ratelimit.lua",
        ["motebase.rules"] = "motebase/rules/init.lua",
        ["motebase.rules.parser"] = "motebase/rules/parser.lua",
        ["motebase.rules.eval"] = "motebase/rules/eval.lua",
        ["motebase.realtime"] = "motebase/realtime/init.lua",
        ["motebase.realtime.broker"] = "motebase/realtime/broker.lua",
        ["motebase.realtime.client"] = "motebase/realtime/client.lua",
        ["motebase.realtime.sse"] = "motebase/realtime/sse.lua",
        ["motebase.mail"] = "motebase/mail.lua",
        ["motebase.oauth"] = "motebase/oauth.lua",
        ["motebase.hooks"] = "motebase/hooks.lua",
        ["motebase.admin"] = "motebase/admin/init.lua",
        ["motebase.logs"] = "motebase/logs.lua",
        ["motebase.settings"] = "motebase/settings.lua",
        ["motebase.s3"] = "motebase/s3.lua",
        ["motebase.storage.s3"] = "motebase/storage/s3.lua",
    },
    install = {
        bin = {
            ["motebase"] = "bin/motebase.lua",
        },
    },
    copy_directories = {
        "motebase/admin",
    },
}
