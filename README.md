<div align="center">

# motebase

PocketBase, but smaller.

[![License: MIT](https://img.shields.io/badge/license-MIT-000080)](LICENSE)

</div>

## Features

<table>
<tr>
<td width="50%">

**Dynamic Collections**

Create collections with typed schemas at runtime. Auto-generated CRUD endpoints.

</td>
<td width="50%">

**JWT Authentication**

Register, login, and protect routes with JWT tokens. HMAC-SHA256 signing with `jti` for revocation support.

</td>
</tr>
<tr>
<td width="50%">

**SQLite Storage**

Self-contained database with WAL mode. No external database required.

</td>
<td width="50%">

**Tiny Footprint**

Pure Lua implementation. No C dependencies except LuaSocket and SQLite. Lua 5.1+ compatible (LuaJIT ready).

</td>
</tr>
</table>

## Comparison

| | Supabase | PocketBase | MoteBase |
|---|----------|------------|----------|
| Size | ~2GB+ | ~50MB | ~1.4MB |
| Boot time | Seconds | ~1 second | <100ms |
| Self-contained | No | Yes | Yes |
| Static binary | No | Yes | Yes |

## Installation

### Static Binary

```bash
curl -L https://github.com/pgagnidze/motebase/releases/latest/download/motebase-bin-linux_x86_64 -o motebase
chmod +x motebase
./motebase
```

### Docker

```bash
docker pull ghcr.io/pgagnidze/motebase:latest
```

See [Deployment](#deployment) for docker-compose with automatic HTTPS.

### From Source

```bash
# Dependencies (Fedora/RHEL)
sudo dnf install lua lua-devel luarocks gcc sqlite-devel

# Dependencies (Ubuntu/Debian)
sudo apt install lua5.4 liblua5.4-dev luarocks gcc libsqlite3-dev

# Install
luarocks --local install luasocket lsqlite3complete lua-cjson
eval "$(luarocks path --bin)"

# Run
./bin/motebase.lua
```

## Usage

```bash
# Start server
./bin/motebase.lua

# With custom port
./bin/motebase.lua -p 3000

# With all options
./bin/motebase.lua --port 3000 --host 127.0.0.1 --db myapp.db --secret my-secret-key
```

### CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --port` | Port to listen on | `8080` |
| `-h, --host` | Host to bind to | `0.0.0.0` |
| `-d, --db` | Database file path | `motebase.db` |
| `-s, --secret` | JWT secret key | `change-me-in-production` |
| `--help` | Show help message | |
| `-v, --version` | Show version | |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MOTEBASE_SECRET` | JWT secret key | `change-me-in-production` |
| `MOTEBASE_DB` | Database file path | `motebase.db` |
| `MOTEBASE_LOG` | Enable logging (`0` to disable) | enabled |

## API

### Health

```bash
GET /health
# {"status":"ok"}
```

### Collections

```bash
# Create collection
POST /api/collections
{"name":"posts","schema":{"title":{"type":"string","required":true},"body":{"type":"text"}}}

# List collections
GET /api/collections

# Delete collection
DELETE /api/collections/:name
```

### Records

```bash
# Create record
POST /api/collections/:name/records
{"title":"Hello World","body":"My first post"}

# List records
GET /api/collections/:name/records

# Get record
GET /api/collections/:name/records/:id

# Update record
PATCH /api/collections/:name/records/:id
{"title":"Updated Title"}

# Delete record
DELETE /api/collections/:name/records/:id
```

### Authentication

```bash
# Register
POST /api/auth/register
{"email":"user@example.com","password":"password123"}

# Login
POST /api/auth/login
{"email":"user@example.com","password":"password123"}
# Returns {"token":"eyJ...","user":{"id":1,"email":"user@example.com"}}

# Get current user (requires Authorization header)
GET /api/auth/me
Authorization: Bearer <token>
```

### JWT Token Structure

Tokens include standard claims plus security enhancements:

| Claim | Description |
|-------|-------------|
| `sub` | User ID |
| `iat` | Issued at timestamp |
| `exp` | Expiration timestamp |
| `jti` | Unique token ID (for revocation) |
| `aud` | Audience (optional, for multi-service) |
| `iss` | Issuer (optional) |

### Schema Types

| Type | SQL Type | Description |
|------|----------|-------------|
| `string` | TEXT | Short text |
| `text` | TEXT | Long text |
| `email` | TEXT | Email with format validation |
| `number` | REAL | Numeric value |
| `boolean` | INTEGER | True/false (stored as 1/0) |
| `json` | TEXT | JSON object |

### Field Options

| Option | Type | Description |
|--------|------|-------------|
| `type` | string | Field type (see above) |
| `required` | boolean | Field must be present (default: false) |

## Example

```bash
# Start server
./bin/motebase.lua &

# Create a collection
curl -X POST http://localhost:8080/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"todos","schema":{"task":{"type":"string","required":true},"done":{"type":"boolean"}}}'

# Add a todo
curl -X POST http://localhost:8080/api/collections/todos/records \
  -H "Content-Type: application/json" \
  -d '{"task":"Build something cool","done":false}'

# List todos
curl http://localhost:8080/api/collections/todos/records
```

## Architecture

```
motebase/
├── bin/motebase.lua       # Entry point
├── motebase/
│   ├── init.lua           # Main module, routes
│   ├── server.lua         # Async HTTP server (coroutines + select)
│   ├── router.lua         # URL routing
│   ├── auth.lua           # User registration/login
│   ├── jwt.lua            # JWT encoding/decoding
│   ├── collections.lua    # Dynamic collections CRUD
│   ├── schema.lua         # Field validation
│   ├── db.lua             # SQLite wrapper
│   ├── middleware.lua     # CORS, JSON parsing
│   ├── crypto/            # Pure Lua cryptography
│   │   ├── init.lua       # Base64, random, comparison
│   │   ├── sha256.lua     # SHA-256 hash
│   │   ├── hmac.lua       # HMAC-SHA256
│   │   └── bit.lua        # Lua 5.1+ bit operations
│   └── utils/             # Utilities
│       ├── output.lua     # Terminal colors
│       └── log.lua        # Security logging
└── spec/                  # Tests (busted)
```

## Deployment

### Docker Compose (Recommended)

The included `docker-compose.yml` runs MoteBase with Caddy for automatic HTTPS:

```bash
# Development (self-signed cert for localhost)
docker compose up -d

# Production (auto Let's Encrypt cert)
DOMAIN=api.example.com MOTEBASE_SECRET=your-secret docker compose up -d
```

### Manual Reverse Proxy

MoteBase runs HTTP without TLS. For production without Docker, use a reverse proxy:

**Caddy** (automatic HTTPS):

```
example.com {
    reverse_proxy localhost:8080
}
```

**nginx**:

```nginx
server {
    listen 443 ssl;
    server_name example.com;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Development

```bash
# Run from source
./bin/motebase.lua

# Run linter
luacheck motebase/ bin/ spec/

# Format code
stylua motebase/ bin/

# Run tests
busted spec/

# Run tests without logging
MOTEBASE_LOG=0 busted spec/
```

## License

[MIT](LICENSE)
