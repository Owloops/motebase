<div align="center">

# motebase

PocketBase, but smaller.

[![CI](https://github.com/pgagnidze/motebase/actions/workflows/ci.yml/badge.svg)](https://github.com/pgagnidze/motebase/actions/workflows/ci.yml)
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

Register, login, and protect routes. HMAC-SHA256 signing with `jti` for revocation.

</td>
</tr>
<tr>
<td width="50%">

**SQLite Storage**

Self-contained database with WAL mode. No external dependencies.

</td>
<td width="50%">

**Tiny Footprint**

Small codebase, tiny binary, minimal Docker image.

</td>
</tr>
</table>

## Comparison

| | Supabase | PocketBase | MoteBase |
|---|----------|------------|----------|
| Size | ~2GB+ | ~50MB | ~2MB |
| Boot time | >1s | ~1s | <100ms |
| Self-contained | No | Yes | Yes |

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
| `--help` | Show help message | |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MOTEBASE_SECRET` | JWT secret key |
| `MOTEBASE_DB` | Database file path |
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

## License

[MIT](LICENSE)
