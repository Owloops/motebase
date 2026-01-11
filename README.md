<div align="center">

<img src="assets/motebase.svg" alt="motebase logo" width="128"/>

# motebase

Tiny self-hosted PocketBase alternative.

[![CI](https://github.com/owloops/motebase/actions/workflows/ci.yml/badge.svg)](https://github.com/owloops/motebase/actions/workflows/ci.yml)
[![LuaRocks](https://img.shields.io/luarocks/v/pgagnidze/motebase?color=000080)](https://luarocks.org/modules/pgagnidze/motebase)
[![License: MIT](https://img.shields.io/badge/license-MIT-000080)](LICENSE)

</div>

## Features

<table>
<tr>
<td width="50%">

**Dynamic Collections**

Create collections with typed schemas at runtime. Auto-generated CRUD endpoints with filtering, sorting, and pagination.

</td>
<td width="50%">

**JWT Auth & API Rules**

Register, login, and protect routes. PocketBase-compatible access control per collection.

</td>
</tr>
<tr>
<td width="50%">

**Relations & Realtime**

Link records between collections. Subscribe to changes via Server-Sent Events.

</td>
<td width="50%">

**Background Jobs & Cron**

SQLite-backed job queue with retries. Built-in cron scheduler for recurring tasks.

</td>
</tr>
<tr>
<td width="50%">

**Tiny Footprint**

~2MB binary. <25ms startup. SQLite + filesystem storage. LuaJIT-powered.

</td>
</tr>
</table>

> **Note:** Background jobs require running `motebase worker` alongside `motebase serve`. Cron tasks run automatically in the serve process.

## Installation

### Install Script

```bash
curl -fsSL https://raw.githubusercontent.com/owloops/motebase/main/install.sh | bash
```

### Static Binary

Available binaries: `linux_x86_64`, `linux_arm64`, `darwin_x86_64`, `darwin_arm64`

```bash
curl -L https://github.com/owloops/motebase/releases/latest/download/motebase-bin-linux_x86_64 -o motebase
chmod +x motebase
./motebase
```

### Docker

```bash
docker pull ghcr.io/owloops/motebase:latest
```

See [Deployment](#deployment) for docker-compose with automatic HTTPS.

### From Source

```bash
# Install dependencies
luarocks --local install luasocket lsqlite3complete lua-cjson luafilesystem lpeg
eval "$(luarocks path --bin)"

# Run with Lua 5.4
lua ./bin/motebase.lua

# Or with LuaJIT (recommended, better performance)
luajit ./bin/motebase.lua
```

> **Note:** Both Lua 5.4 and LuaJIT are supported. LuaJIT is recommended for production as it provides better performance in our testing. Static binaries are built with LuaJIT.

## Usage

```bash
# Start server (HTTP + cron scheduler)
./motebase serve

# Start background job worker (in separate terminal)
./motebase worker

# With options
./motebase serve --port 3000 --host 127.0.0.1 --db myapp.db --secret my-secret-key
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --port` | Port to listen on | `8097` |
| `-h, --host` | Host to bind to | `0.0.0.0` |
| `-d, --db` | Database file path | `motebase.db` |
| `-s, --secret` | JWT secret key | `change-me-in-production` |
| `--storage` | File storage directory | `./storage` |
| `--superuser` | Superuser email address | First registered user |
| `--ratelimit` | Requests per minute (0 to disable) | `100` |
| `--max-connections` | Max concurrent connections | `10000` |
| `-H, --hooks` | Lua file for custom hooks/routes | |
| `--help` | Show help message | |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MOTEBASE_SECRET` | JWT secret key |
| `MOTEBASE_DB` | Database file path |
| `MOTEBASE_STORAGE` | File storage directory |
| `MOTEBASE_SUPERUSER` | Superuser email address |
| `MOTEBASE_RATELIMIT` | Requests per minute (0 to disable) |
| `MOTEBASE_MAX_CONNECTIONS` | Max concurrent connections |
| `MOTEBASE_LOG` | Enable logging (`0` to disable) |
| `MOTEBASE_DEV` | Dev mode - reload admin UI files on each request (`1` to enable) |

#### SMTP (Email)

| Variable | Description | Default |
|----------|-------------|---------|
| `MOTEBASE_SMTP_HOST` | SMTP server hostname | |
| `MOTEBASE_SMTP_PORT` | SMTP server port (TLS) | `465` |
| `MOTEBASE_SMTP_USER` | SMTP username | |
| `MOTEBASE_SMTP_PASS` | SMTP password | |
| `MOTEBASE_SMTP_FROM` | From email address | |

#### OAuth

| Variable | Description |
|----------|-------------|
| `MOTEBASE_OAUTH_GOOGLE_ID` | Google OAuth client ID |
| `MOTEBASE_OAUTH_GOOGLE_SECRET` | Google OAuth client secret |
| `MOTEBASE_OAUTH_GITHUB_ID` | GitHub OAuth client ID |
| `MOTEBASE_OAUTH_GITHUB_SECRET` | GitHub OAuth client secret |
| `MOTEBASE_OAUTH_REDIRECT_URL` | OAuth callback base URL (e.g., `https://api.example.com`) |

#### S3 Storage

| Variable | Description | Default |
|----------|-------------|---------|
| `MOTEBASE_STORAGE_BACKEND` | Storage backend (`local` or `s3`) | `local` |
| `MOTEBASE_S3_BUCKET` | S3 bucket name | |
| `MOTEBASE_S3_REGION` | AWS region | `us-east-1` |
| `MOTEBASE_S3_ENDPOINT` | S3 endpoint (for non-AWS services) | Auto |
| `MOTEBASE_S3_ACCESS_KEY` | S3 access key ID | |
| `MOTEBASE_S3_SECRET_KEY` | S3 secret access key | |
| `MOTEBASE_S3_PATH_STYLE` | Use path-style URLs (`true`/`false`) | `false` |
| `MOTEBASE_S3_USE_SSL` | Use HTTPS for S3 (`true`/`false`) | `true` |

**AWS S3:**
```bash
MOTEBASE_STORAGE_BACKEND=s3 \
MOTEBASE_S3_BUCKET=my-app-files \
MOTEBASE_S3_REGION=us-west-2 \
MOTEBASE_S3_ACCESS_KEY=AKIA... \
MOTEBASE_S3_SECRET_KEY=secret \
./motebase
```

**Cloudflare R2:**
```bash
MOTEBASE_STORAGE_BACKEND=s3 \
MOTEBASE_S3_BUCKET=my-app-files \
MOTEBASE_S3_REGION=auto \
MOTEBASE_S3_ENDPOINT=<account>.r2.cloudflarestorage.com \
MOTEBASE_S3_ACCESS_KEY=... \
MOTEBASE_S3_SECRET_KEY=... \
MOTEBASE_S3_PATH_STYLE=true \
./motebase
```

**MinIO (self-hosted):**
```bash
MOTEBASE_STORAGE_BACKEND=s3 \
MOTEBASE_S3_BUCKET=my-app-files \
MOTEBASE_S3_ENDPOINT=minio.local:9000 \
MOTEBASE_S3_ACCESS_KEY=minioadmin \
MOTEBASE_S3_SECRET_KEY=minioadmin \
MOTEBASE_S3_PATH_STYLE=true \
MOTEBASE_S3_USE_SSL=false \
./motebase
```

## API

### Collections

```bash
# Create collection with schema
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"posts","schema":{"title":{"type":"string","required":true},"body":{"type":"text"}}}'

# List collections
curl http://localhost:8097/api/collections

# Delete collection
curl -X DELETE http://localhost:8097/api/collections/posts
```

### Records

```bash
# Create record
curl -X POST http://localhost:8097/api/collections/posts/records \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello World","body":"My first post"}'

# List records
curl http://localhost:8097/api/collections/posts/records

# Get record
curl http://localhost:8097/api/collections/posts/records/1

# Update record
curl -X PATCH http://localhost:8097/api/collections/posts/records/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Updated Title"}'

# Delete record
curl -X DELETE http://localhost:8097/api/collections/posts/records/1
```

### Query & Filter

List records with filtering, sorting, pagination, and field selection:

```bash
# Filter records (PocketBase-compatible syntax)
curl "http://localhost:8097/api/collections/posts/records?filter=status='published'"

# Multiple conditions
curl "http://localhost:8097/api/collections/posts/records?filter=status='published'%20%26%26%20views>100"

# Sort (- for descending)
curl "http://localhost:8097/api/collections/posts/records?sort=-created_at,title"

# Pagination
curl "http://localhost:8097/api/collections/posts/records?page=2&perPage=10"

# Select fields
curl "http://localhost:8097/api/collections/posts/records?fields=id,title,status"

# Combined
curl "http://localhost:8097/api/collections/posts/records?filter=status='published'&sort=-views&page=1&perPage=10&fields=id,title"

# Skip total count (faster for large datasets)
curl "http://localhost:8097/api/collections/posts/records?skipTotal=true"
```

#### Filter Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equal | `status='active'` |
| `!=` | Not equal | `status!='deleted'` |
| `>` | Greater than | `views>100` |
| `>=` | Greater or equal | `views>=100` |
| `<` | Less than | `views<100` |
| `<=` | Less or equal | `views<=100` |
| `~` | Like/Contains | `title~'hello'` |
| `!~` | Not like | `title!~'spam'` |
| `?=` | Any equal (arrays) | `tags?='lua'` |
| `?!=`, `?>`, etc. | Any-of variants | `scores?>50` |
| `&&` | AND | `a='x' && b='y'` |
| `\|\|` | OR | `a='x' \|\| a='y'` |
| `()` | Grouping | `(a='x' \|\| a='y') && b='z'` |

#### Response Format

```json
{
  "page": 1,
  "perPage": 20,
  "totalItems": 100,
  "totalPages": 5,
  "items": [...]
}
```

### Relations

Link records between collections using relation fields:

```bash
# Create users collection (returns collection with id)
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"users","schema":{"name":{"type":"string","required":true}}}'
# Response: {"id":"abc123...","name":"users",...}

# Create posts collection with author relation (use the users collection id)
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"posts","schema":{"title":{"type":"string","required":true},"author":{"type":"relation","collectionId":"abc123..."}}}'

# Create user
curl -X POST http://localhost:8097/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice"}'

# Create post with relation
curl -X POST http://localhost:8097/api/collections/posts/records \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello World","author":1}'
```

> **Note:** Relation fields use `collectionId` (the target collection's ID) rather than collection name. This ensures relations survive collection renames.

#### Multiple Relations

Store arrays of references using `multiple: true`:

```bash
# Create tags collection
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"tags","schema":{"name":{"type":"string","required":true}}}'
# Response: {"id":"xyz789...","name":"tags",...}

# Create articles with multiple tags (use the tags collection id)
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"articles","schema":{"title":{"type":"string"},"tags":{"type":"relation","collectionId":"xyz789...","multiple":true}}}'

# Create article with tag IDs
curl -X POST http://localhost:8097/api/collections/articles/records \
  -H "Content-Type: application/json" \
  -d '{"title":"My Article","tags":[1,2,3]}'
```

### Expand

Fetch related records inline using `?expand=`:

```bash
# Expand single relation
curl "http://localhost:8097/api/collections/posts/records?expand=author"

# Expand multiple fields
curl "http://localhost:8097/api/collections/articles/records?expand=author,tags"

# Nested expand
curl "http://localhost:8097/api/collections/posts/records?expand=author.company"

# Back-relation (get posts by user)
curl "http://localhost:8097/api/collections/users/records?expand=posts_via_author"

# Single record with expand
curl "http://localhost:8097/api/collections/posts/records/1?expand=author"
```

#### Expand Response

```json
{
  "id": 1,
  "title": "Hello World",
  "author": "1",
  "expand": {
    "author": {
      "id": 1,
      "name": "Alice"
    }
  }
}
```

#### Expand Syntax

| Pattern | Description | Example |
|---------|-------------|---------|
| `field` | Single relation | `?expand=author` |
| `field1,field2` | Multiple fields | `?expand=author,tags` |
| `field.nested` | Nested expand | `?expand=author.company` |
| `collection_via_field` | Back-relation | `?expand=posts_via_author` |

### Authentication

```bash
# Register
curl -X POST http://localhost:8097/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}'

# Login (returns JWT token)
curl -X POST http://localhost:8097/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}'

# Get current user
curl http://localhost:8097/api/auth/me \
  -H "Authorization: Bearer <token>"
```

#### Password Reset

Requires SMTP configuration.

```bash
# Request password reset (sends email)
curl -X POST http://localhost:8097/api/auth/request-password-reset \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","app_url":"https://myapp.com"}'

# Confirm password reset (with token from email)
curl -X POST http://localhost:8097/api/auth/confirm-password-reset \
  -H "Content-Type: application/json" \
  -d '{"token":"<reset_token>","password":"newpassword123"}'
```

#### Email Verification

Requires SMTP configuration and authentication.

```bash
# Request verification email (requires auth)
curl -X POST http://localhost:8097/api/auth/request-verification \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"app_url":"https://myapp.com"}'

# Confirm verification (with token from email)
curl -X POST http://localhost:8097/api/auth/confirm-verification \
  -H "Content-Type: application/json" \
  -d '{"token":"<verification_token>"}'
```

#### OAuth

Requires OAuth environment variables for the provider.

```bash
# List available providers
curl http://localhost:8097/api/auth/oauth/providers
# Returns: {"providers":["google","github"]}

# Start OAuth flow (redirect user to this URL)
curl http://localhost:8097/api/auth/oauth/google
# Returns: {"url":"https://accounts.google.com/o/oauth2/v2/auth?..."}

# OAuth callback (handled automatically, returns JWT)
# GET /api/auth/oauth/google/callback?code=...&state=...
```

**Supported Providers:**

| Provider | Scopes |
|----------|--------|
| Google | `openid`, `email`, `profile` |
| GitHub | `user:email` |

### Schema Types

| Type | Description |
|------|-------------|
| `string` | Short text |
| `text` | Long text |
| `email` | Email with validation |
| `number` | Numeric value |
| `boolean` | True/false |
| `json` | JSON object |
| `file` | File upload (see File Storage) |
| `relation` | Reference to another collection (see Relations) |

### File Storage

```bash
# Create collection with file field
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"docs","schema":{"title":{"type":"string"},"attachment":{"type":"file"}}}'

# Upload file with record
curl -X POST http://localhost:8097/api/collections/docs/records \
  -F "title=My Document" \
  -F "attachment=@document.pdf"

# Download file
curl http://localhost:8097/api/files/docs/1/document_abc123.pdf -o file.pdf
```

#### Protected Files

Mark file fields as protected to require token-based access:

```bash
# Create collection with protected file
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"private","schema":{"doc":{"type":"file","protected":true}}}'

# Get file token (requires auth)
curl -X POST http://localhost:8097/api/files/token \
  -H "Authorization: Bearer <token>"
# Returns: {"token":"...","expires":120}

# Access protected file with token
curl "http://localhost:8097/api/files/private/1/doc_abc123.pdf?token=<file_token>"
```

### Realtime (SSE)

Subscribe to collection changes via Server-Sent Events:

```bash
# Open SSE connection (returns client ID)
curl -N http://localhost:8097/api/realtime
# Output: id:abc123... event:MB_CONNECT data:{"clientId":"abc123..."}

# Subscribe to collection changes
curl -X POST http://localhost:8097/api/realtime \
  -H "Content-Type: application/json" \
  -d '{"clientId":"abc123...","subscriptions":["posts/*"]}'
```

When records are created, updated, or deleted, subscribed clients receive events:

```
id:abc123...
event:posts/*
data:{"action":"create","record":{"id":1,"title":"Hello",...}}
```

#### Subscription Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| `collection/*` | All records in collection | `posts/*` |
| `collection/id` | Specific record | `posts/123` |

### API Rules

Control access to collections with PocketBase-compatible rules:

```bash
# Create collection with rules (assuming users collection id is "abc123...")
curl -X POST http://localhost:8097/api/collections \
  -H "Content-Type: application/json" \
  -d '{
    "name": "posts",
    "schema": {"title": {"type": "string"}, "author": {"type": "relation", "collectionId": "abc123..."}},
    "listRule": "",
    "viewRule": "",
    "createRule": "@request.auth.id != \"\"",
    "updateRule": "author = @request.auth.id",
    "deleteRule": null
  }'

# Update rules on existing collection
curl -X PATCH http://localhost:8097/api/collections/posts \
  -H "Content-Type: application/json" \
  -d '{"listRule": "status = \"published\""}'
```

#### Rule Values

| Value | Meaning |
|-------|---------|
| `null` | Superuser only (locked) |
| `""` | Anyone (public access) |
| `"expression"` | Users matching the filter |

#### Rule Syntax

```bash
# Authenticated users only
@request.auth.id != ""

# Owner only
author = @request.auth.id

# Role-based
@request.auth.role = "admin" || @request.auth.role = "editor"

# Record field + auth combined
status = "published" || author = @request.auth.id

# Time-based
expiry > @now

# Prevent field changes
@request.body.role:isset = false

# Check if field was modified
@request.body.status:changed = false
```

#### Supported Identifiers

| Identifier | Description |
|------------|-------------|
| `@request.auth.*` | Current user fields |
| `@request.body.*` | Submitted data |
| `@request.query.*` | Query parameters |
| `@request.headers.*` | Request headers |
| `@request.method` | HTTP method |
| `@request.context` | Request context |
| `@now`, `@yesterday`, `@tomorrow` | Datetime macros |
| `@todayStart`, `@todayEnd`, etc. | Date boundaries |

#### Modifiers

| Modifier | Description | Example |
|----------|-------------|---------|
| `:isset` | Check if field was submitted | `@request.body.role:isset = false` |
| `:changed` | Check if field was modified | `@request.body.status:changed = false` |
| `:length` | Array/string length | `tags:length > 0` |
| `:each` | All items match | `tags:each ~ "valid"` |
| `:lower` | Case-insensitive | `title:lower = "test"` |

## Background Jobs

Queue long-running tasks to be processed by a separate worker process:

```bash
# Start worker (separate terminal)
./motebase worker
```

### Queueing Jobs

```lua
-- hooks.lua
local motebase = require("motebase")

-- Queue a job
motebase.queue("send_email", { to = "user@example.com", subject = "Hello" })

-- With options
motebase.queue("process_video", { video_id = 123 }, {
    priority = "high",      -- high, normal, low
    delay = 300,            -- delay in seconds
    attempts = 3,           -- max retry attempts
    timeout = 3600,         -- timeout in seconds (default: 30 min)
})
```

### Registering Handlers

```lua
-- hooks.lua
local motebase = require("motebase")

motebase.on_job("send_email", function(payload)
    -- payload contains { to = "...", subject = "..." }
    send_email(payload.to, payload.subject)
    return { sent = true }  -- optional result
end)

motebase.on_job("process_video", function(payload)
    -- Long-running task processed by worker
    process(payload.video_id)
end)
```

### Job Management CLI

```bash
# List jobs
./motebase jobs list
./motebase jobs list --status pending
./motebase jobs list --status failed

# View statistics
./motebase jobs stats

# Retry failed jobs
./motebase jobs retry <job_id>
./motebase jobs retry --all

# Delete jobs
./motebase jobs delete <job_id>

# Clear completed/failed jobs
./motebase jobs clear
./motebase jobs clear --status completed
```

### How It Works

```
┌─────────────────┐     ┌─────────────────┐
│ motebase serve  │     │ motebase worker │
│  ─────────────  │     │  ─────────────  │
│  HTTP requests  │     │  Polls _jobs    │
│  Queue jobs     │────▶│  Runs handlers  │
│  Cron scheduler │     │  Retries/fails  │
└─────────────────┘     └─────────────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
              ┌─────────────┐
              │   SQLite    │
              │  _jobs tbl  │
              └─────────────┘
```

- **Persistence**: Jobs survive restarts (stored in SQLite)
- **Retries**: Failed jobs retry with exponential backoff
- **Timeouts**: Stale running jobs are automatically failed
- **Priority**: High priority jobs are processed first
- **No external deps**: Just SQLite, no Redis/RabbitMQ needed

## Cron Scheduler

Built-in cron runs in the serve process for recurring tasks:

```lua
-- hooks.lua
local cron = require("motebase.cron")

-- Standard cron expression (minute hour day month weekday)
cron.add("cleanup", "0 3 * * *", function()
    -- Runs daily at 3:00 AM
    cleanup_old_records()
end)

-- Every 5 minutes
cron.add("health_check", "*/5 * * * *", function()
    check_services()
end)

-- Macros supported
cron.add("weekly_report", "@weekly", function()
    generate_report()
end)
```

### Cron Expression Syntax

| Field | Values | Special Characters |
|-------|--------|-------------------|
| Minute | 0-59 | `*` `,` `-` `/` |
| Hour | 0-23 | `*` `,` `-` `/` |
| Day | 1-31 | `*` `,` `-` `/` |
| Month | 1-12 | `*` `,` `-` `/` |
| Weekday | 0-6 (Sun=0) | `*` `,` `-` `/` |

### Macros

| Macro | Equivalent |
|-------|------------|
| `@yearly` | `0 0 1 1 *` |
| `@monthly` | `0 0 1 * *` |
| `@weekly` | `0 0 * * 0` |
| `@daily` | `0 0 * * *` |
| `@hourly` | `0 * * * *` |

### Built-in Cron Jobs

MoteBase includes automatic maintenance tasks:

| Job | Schedule | Description |
|-----|----------|-------------|
| Log cleanup | Every 6 hours | Delete logs older than 7 days |
| DB optimize | Daily 3 AM | WAL checkpoint + PRAGMA optimize |
| Job cleanup | Daily 4 AM | Delete completed jobs older than 7 days |
| Job timeout | Every 5 min | Fail stale running jobs |

### Cron Management CLI

```bash
# List registered cron jobs
./motebase cron list
```

## Deployment

### Docker Compose (Recommended)

The included `docker-compose.yml` runs MoteBase with Caddy for automatic HTTPS:

```bash
# Development (self-signed cert for localhost)
docker compose up -d

# Production (auto Let's Encrypt cert)
DOMAIN=api.example.com MOTEBASE_SECRET=your-secret docker compose up -d

# With email support (for password reset, verification)
DOMAIN=api.example.com \
MOTEBASE_SECRET=your-secret \
MOTEBASE_SMTP_HOST=smtp.example.com \
MOTEBASE_SMTP_USER=user \
MOTEBASE_SMTP_PASS=pass \
MOTEBASE_SMTP_FROM=noreply@example.com \
docker compose up -d
```

The compose file includes three services:
- `mote` - HTTP server + cron scheduler
- `worker` - Background job processor (emails, etc.)
- `caddy` - Reverse proxy with automatic HTTPS

### Manual Reverse Proxy

MoteBase runs HTTP without TLS. For production, use a reverse proxy:

```
# Caddyfile
example.com {
    reverse_proxy localhost:8097
}
```

## Hooks

Extend MoteBase with custom Lua code loaded at startup:

```bash
motebase --hooks hooks.lua
```

### Full Internal Access

All modules are available via `require()`:

| Module | Description |
|--------|-------------|
| `motebase.db` | Database operations |
| `motebase.auth` | Authentication |
| `motebase.collections` | CRUD operations |
| `motebase.router` | Route registration |
| `motebase.server` | Response helpers (json, error, redirect) |
| `motebase.jwt` | JWT encoding/decoding |
| `motebase.files` | File storage |
| `motebase.realtime` | SSE broadcasting |
| `motebase.rules` | Rule evaluation |
| `motebase.mail` | Email sending |
| `motebase.oauth` | OAuth providers |
| `motebase.jobs` | Background job queue |
| `motebase.cron` | Cron scheduler |

Wrap any function to add custom behavior:

```lua
-- hooks.lua
local auth = require("motebase.auth")

local original_login = auth.login
auth.login = function(email, password, secret, expires_in)
    print("login attempt: " .. email)
    local result, err = original_login(email, password, secret, expires_in)
    if result then print("login success: " .. email) end
    return result, err
end
```

### Custom Routes

```lua
local router = require("motebase.router")
local server = require("motebase.server")
local db = require("motebase.db")

router.post("/api/checkout", function(ctx)
    -- ctx.user contains JWT payload if authenticated: sub (user_id), iat, exp, jti
    -- ctx.body contains request JSON
    server.json(ctx, 200, { status = "ok", user_id = ctx.user and ctx.user.sub })
end)

router.get("/api/stats", function(ctx)
    local result = db.query("SELECT COUNT(*) as count FROM posts")
    server.json(ctx, 200, { posts = result[1].count })
end)
```

**Response helpers:** `server.json(ctx, status, data)`, `server.error(ctx, status, message)`, `server.redirect(ctx, url)`

### Convenience Helpers

For common patterns, use the hooks module:

```lua
local hooks = require("motebase.hooks")

-- Before hooks can modify data or cancel operations
hooks.before_create("orders", function(record, ctx)
    record.total = calculate_total(record.items)
    return record  -- return modified record
    -- return nil, "error message" to cancel
end)

-- After hooks for side effects
hooks.after_create("orders", function(record, ctx)
    send_order_confirmation(record)
end)

-- Wildcard for all collections
hooks.before_create("*", function(record, ctx)
    record.created_by = ctx.user and ctx.user.sub
    return record
end)
```

Available hooks: `before_create`, `after_create`, `before_update`, `after_update`, `before_delete`, `after_delete`

### External Modules

Place `.lua` files in the same directory as your hooks file:

```
myapp/
├── hooks.lua        # require("mylib") works
├── mylib.lua
└── utils/
    └── helpers.lua  # require("utils.helpers") works
```

Or add luarocks paths for pure Lua modules:

```lua
-- hooks.lua
package.path = package.path .. ";?.lua;?/init.lua"

local inspect = require("inspect")
```

**Note:** C modules (`.so` files) are not supported in the static binary.

### External API Integration

Hooks have full access to HTTP clients for calling external APIs:

```lua
local http = require("socket.http")
local ltn12 = require("ltn12")

router.get("/api/external", function(ctx)
    local response = {}
    http.request({
        url = "https://api.example.com/data",
        sink = ltn12.sink.table(response),
    })
    server.json(ctx, 200, { data = table.concat(response) })
end)
```

**Bundled libraries:** `socket.http`, `ltn12`, `cjson`, `lpeg`, `lfs`

## Development

```bash
./bin/motebase.lua           # Run from source
busted                       # Run tests
luacheck .                   # Lint
stylua .                     # Format
```

## Credits

- [LPeg-Parsers](https://github.com/spc476/LPeg-Parsers) by Sean Conner (LGPL-3.0)
- [lua-hashings](https://github.com/user-none/lua-hashings) by John Schember (MIT)

## License

[MIT](LICENSE)
