# Caddy HTTPS Server — Unraid Docker Design

**Date:** 2026-05-04  
**Status:** Approved

## Overview

A Dockerized Caddy web server for Unraid that serves multiple HTTPS subdomains using Cloudflare DNS challenge for TLS certificates. Supports both static file serving (read-only mount) and reverse proxy to other containers.

## Architecture

Multi-stage Dockerfile:
- **Stage 1 (build):** `golang:alpine` + `xcaddy` compiles Caddy with the `caddy-dns/cloudflare` plugin. Caddy version is pinned for reproducibility.
- **Stage 2 (runtime):** `alpine:3.21` — minimal image with non-root user (`caddy:caddy`). Only the compiled binary is copied over.

## File Structure

```
caddyDocker/
├── Dockerfile
├── docker-compose.yml
├── Caddyfile.example
├── unraid-template.xml
└── docs/superpowers/specs/2026-05-04-caddy-unraid-design.md
```

## Ports

| Container port | Host port | Purpose |
|---|---|---|
| 80 | 8080 | HTTP (redirects to HTTPS) |
| 443 | 8443 | HTTPS |
| 2019 | internal only | Caddy admin API |

Using non-standard host ports to avoid conflicts with other Unraid containers.

## Volumes

| Container path | Mode | Purpose |
|---|---|---|
| `/etc/caddy/Caddyfile` | read-only | Caddy configuration |
| `/srv/www` | **read-only** | Static HTML files |
| `/data` | read-write | TLS certificates (persisted via named volume) |
| `/config` | read-write | Caddy internal state |

## Configuration

**TLS:** Cloudflare DNS challenge via `caddy-dns/cloudflare` plugin. Supports wildcard certificates (`*.domain.com`). Does not require ports 80/443 open to the internet.

**Cloudflare API Token** passed as environment variable `CLOUDFLARE_API_TOKEN`.

**Static files path** configurable via `WWW_PATH` env var in compose / Unraid template field.

**Caddyfile** mounted from host — editable without container rebuild.

## Unraid Template Fields

| Field | Variable | Example |
|---|---|---|
| Cloudflare API Token | `CLOUDFLARE_API_TOKEN` | `abc123...` |
| HTML folder path | `WWW_PATH` | `/mnt/user/appdata/caddy/www` |
| Caddyfile path | volume mapping | `/mnt/user/appdata/caddy/Caddyfile` |
| HTTP port | host port | `8080` |
| HTTPS port | host port | `8443` |

## Caddyfile.example

Will demonstrate:
- Wildcard TLS certificate via Cloudflare DNS challenge
- One subdomio serving static files from `/srv/www`
- One subdomain as reverse proxy to another container

## Security Notes

- Static files folder mounted `:ro` — Caddy process cannot write to it even if compromised
- Runtime container runs as non-root user
- Caddy admin API (port 2019) not exposed to host
- API token passed via env var (visible in `docker inspect` — acceptable tradeoff for simplicity)
