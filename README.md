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

Create collections with typed schemas at runtime. Auto-generated CRUD endpoints.

</td>
<td width="50%">

**Query & Filter**

PocketBase-compatible filter syntax. Sort, paginate, and select fields.

</td>
</tr>
<tr>
<td width="50%">

**JWT Authentication**

Register, login, and protect routes. HMAC-SHA256 signing with `jti` for revocation.

</td>
<td width="50%">

**File Storage**

Upload files via multipart forms. Protected files with short-lived tokens.

</td>
</tr>
<tr>
<td width="50%">

**SQLite + Filesystem**

Self-contained database with WAL mode. Files on disk with metadata in SQLite.

</td>
<td width="50%">

**Tiny Footprint**

~2MB binary. ~2MB Docker image. Pure Lua, cross-platform.

</td>
</tr>
</table>

## Comparison

| | Supabase | PocketBase | MoteBase |
|---|----------|------------|----------|
| Size | ~2GB+ | ~50MB | ~2MB |
| Boot time | >1s | ~1s | <100ms |
| Self-contained | No | Yes | Yes |
| Filter syntax | PostgREST | Custom | PocketBase-compatible |

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
luarocks --local install luasocket lsqlite3complete lua-cjson
eval "$(luarocks path --bin)"

# Run
./bin/motebase.lua
```

## Usage

```bash
# Start server
./motebase

# With options
./motebase --port 3000 --host 127.0.0.1 --db myapp.db --secret my-secret-key
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --port` | Port to listen on | `8080` |
| `-h, --host` | Host to bind to | `0.0.0.0` |
| `-d, --db` | Database file path | `motebase.db` |
| `-s, --secret` | JWT secret key | `change-me-in-production` |
| `--storage` | File storage directory | `./storage` |
| `--help` | Show help message | |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MOTEBASE_SECRET` | JWT secret key |
| `MOTEBASE_DB` | Database file path |
| `MOTEBASE_STORAGE` | File storage directory |
| `MOTEBASE_LOG` | Enable logging (`0` to disable) |

## API

### Collections

```bash
# Create collection with schema
curl -X POST http://localhost:8080/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"posts","schema":{"title":{"type":"string","required":true},"body":{"type":"text"}}}'

# List collections
curl http://localhost:8080/api/collections

# Delete collection
curl -X DELETE http://localhost:8080/api/collections/posts
```

### Records

```bash
# Create record
curl -X POST http://localhost:8080/api/collections/posts/records \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello World","body":"My first post"}'

# List records
curl http://localhost:8080/api/collections/posts/records

# Get record
curl http://localhost:8080/api/collections/posts/records/1

# Update record
curl -X PATCH http://localhost:8080/api/collections/posts/records/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Updated Title"}'

# Delete record
curl -X DELETE http://localhost:8080/api/collections/posts/records/1
```

### Query & Filter

List records with filtering, sorting, pagination, and field selection:

```bash
# Filter records (PocketBase-compatible syntax)
curl "http://localhost:8080/api/collections/posts/records?filter=status='published'"

# Multiple conditions
curl "http://localhost:8080/api/collections/posts/records?filter=status='published'%20%26%26%20views>100"

# Sort (- for descending)
curl "http://localhost:8080/api/collections/posts/records?sort=-created_at,title"

# Pagination
curl "http://localhost:8080/api/collections/posts/records?page=2&perPage=10"

# Select fields
curl "http://localhost:8080/api/collections/posts/records?fields=id,title,status"

# Combined
curl "http://localhost:8080/api/collections/posts/records?filter=status='published'&sort=-views&page=1&perPage=10&fields=id,title"

# Skip total count (faster for large datasets)
curl "http://localhost:8080/api/collections/posts/records?skipTotal=true"
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

### Authentication

```bash
# Register
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}'

# Login (returns JWT token)
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}'

# Get current user
curl http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer <token>"
```

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

### File Storage

```bash
# Create collection with file field
curl -X POST http://localhost:8080/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"docs","schema":{"title":{"type":"string"},"attachment":{"type":"file"}}}'

# Upload file with record
curl -X POST http://localhost:8080/api/collections/docs/records \
  -F "title=My Document" \
  -F "attachment=@document.pdf"

# Download file
curl http://localhost:8080/api/files/docs/1/document_abc123.pdf -o file.pdf
```

#### Protected Files

Mark file fields as protected to require token-based access:

```bash
# Create collection with protected file
curl -X POST http://localhost:8080/api/collections \
  -H "Content-Type: application/json" \
  -d '{"name":"private","schema":{"doc":{"type":"file","protected":true}}}'

# Get file token (requires auth)
curl -X POST http://localhost:8080/api/files/token \
  -H "Authorization: Bearer <token>"
# Returns: {"token":"...","expires":120}

# Access protected file with token
curl "http://localhost:8080/api/files/private/1/doc_abc123.pdf?token=<file_token>"
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

MoteBase runs HTTP without TLS. For production, use a reverse proxy:

```
# Caddyfile
example.com {
    reverse_proxy localhost:8080
}
```

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
