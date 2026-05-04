# Caddy Unraid HTTPS Server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Dockerized Caddy server for Unraid that serves multiple HTTPS subdomains via Cloudflare DNS challenge, with static file serving (read-only mount) and reverse proxy support.

**Architecture:** Multi-stage Dockerfile — stage 1 compiles Caddy with the `caddy-dns/cloudflare` plugin using `xcaddy`; stage 2 produces a minimal Alpine runtime image with a non-root user. Configuration (Caddyfile, www folder) is injected at runtime via volumes.

**Tech Stack:** Docker multi-stage build, xcaddy, Caddy v2, caddy-dns/cloudflare plugin, Alpine Linux, docker-compose v2, Unraid Community Applications XML template.

---

### Task 1: Dockerfile (multi-stage build)

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Initialize git repository**

```bash
cd /Code/caddyDocker
git init
git add docs/
git commit -m "chore: initial project structure with design spec and plan"
```

- [ ] **Step 2: Create the Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1

ARG CADDY_VERSION=2.9.1
ARG CLOUDFLARE_PLUGIN_VERSION=v0.2.1

FROM golang:1.24-alpine AS builder

ARG CADDY_VERSION
ARG CLOUDFLARE_PLUGIN_VERSION

RUN apk add --no-cache git && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

RUN xcaddy build "v${CADDY_VERSION}" \
    --with "github.com/caddy-dns/cloudflare@${CLOUDFLARE_PLUGIN_VERSION}" \
    --output /usr/bin/caddy

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S caddy && \
    adduser -S -G caddy caddy

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

RUN mkdir -p /etc/caddy /srv/www /data /config && \
    chown -R caddy:caddy /etc/caddy /srv/www /data /config

USER caddy

EXPOSE 80 443 2019

ENTRYPOINT ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
```

- [ ] **Step 3: Verify Dockerfile syntax**

Run from `/Code/caddyDocker`:
```bash
docker build --no-cache -t caddy-cloudflare:test .
```
Expected: build completes, final image ~50-80MB. Stage 1 will take ~2-3 min first time.

- [ ] **Step 4: Verify caddy binary has cloudflare plugin**

```bash
docker run --rm caddy-cloudflare:test caddy list-modules | grep cloudflare
```
Expected output includes: `dns.providers.cloudflare`

- [ ] **Step 5: Commit**

```bash
git add Dockerfile
git commit -m "feat: multi-stage Dockerfile with caddy-dns/cloudflare plugin"
```

---

### Task 2: Caddyfile.example

**Files:**
- Create: `Caddyfile.example`

- [ ] **Step 1: Create the example Caddyfile**

```caddyfile
# Caddyfile.example
# Copy this to your host path and mount it at /etc/caddy/Caddyfile
#
# Replace "example.com" with your actual domain.
# Replace "CLOUDFLARE_API_TOKEN" with your token env var name.

{
    # Global options
    email your@email.com

    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}

# Wildcard certificate covers all subdomains
*.example.com, example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    # Static files subdominio — served from read-only /srv/www
    @static host static.example.com
    handle @static {
        root * /srv/www
        file_server
    }

    # Reverse proxy subdomain — forwards to another container
    # Replace "192.168.1.100:3000" with your target service host:port
    @app host app.example.com
    handle @app {
        reverse_proxy 192.168.1.100:3000
    }

    # Catch-all for unmatched subdomains
    handle {
        respond "Not found" 404
    }
}
```

- [ ] **Step 2: Validate Caddyfile syntax with Docker**

Create a minimal test Caddyfile at `/tmp/Caddyfile.test`:
```caddyfile
{
    email test@test.com
    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}

*.example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    respond "ok"
}
```

Run:
```bash
docker run --rm \
  -v /tmp/Caddyfile.test:/etc/caddy/Caddyfile:ro \
  caddy-cloudflare:test \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```
Expected: `Valid configuration`

- [ ] **Step 3: Commit**

```bash
git add Caddyfile.example
git commit -m "feat: add Caddyfile.example with wildcard TLS, static and reverse proxy"
```

---

### Task 3: docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create docker-compose.yml**

```yaml
services:
  caddy:
    build: .
    container_name: caddy
    restart: unless-stopped
    ports:
      - "8080:80"
      - "8443:443"
    environment:
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
    volumes:
      - ${CADDYFILE_PATH:-./Caddyfile.example}:/etc/caddy/Caddyfile:ro
      - ${WWW_PATH:-/mnt/user/appdata/caddy/www}:/srv/www:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
```

- [ ] **Step 2: Validate compose file**

```bash
docker compose config
```
Expected: resolved YAML with no errors. `WWW_PATH` and `CADDYFILE_PATH` will show defaults if env vars are not set.

- [ ] **Step 3: Smoke test — container starts without crashing**

Create a minimal valid Caddyfile for local test:
```bash
mkdir -p /tmp/caddy-test/www
echo "<h1>Hello</h1>" > /tmp/caddy-test/www/index.html
```

Create `/tmp/caddy-test/Caddyfile`:
```caddyfile
:80 {
    root * /srv/www
    file_server
}
```

Run:
```bash
CLOUDFLARE_API_TOKEN=dummy \
CADDYFILE_PATH=/tmp/caddy-test/Caddyfile \
WWW_PATH=/tmp/caddy-test/www \
docker compose up -d

docker compose ps
```
Expected: `caddy` service shows `running`.

```bash
curl http://localhost:8080
```
Expected: `<h1>Hello</h1>`

- [ ] **Step 4: Verify /srv/www is read-only inside the container**

```bash
docker compose exec caddy sh -c "touch /srv/www/test.txt 2>&1"
```
Expected: `touch: /srv/www/test.txt: Read-only file system`

- [ ] **Step 5: Tear down test**

```bash
docker compose down
```

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose with configurable paths and read-only www mount"
```

---

### Task 4: Unraid Community Applications XML template

**Files:**
- Create: `unraid-template.xml`

- [ ] **Step 1: Create unraid-template.xml**

```xml
<?xml version="1.0"?>
<Container version="2">
  <Name>caddy-https</Name>
  <Repository>caddy-cloudflare</Repository>
  <Registry/>
  <Network>bridge</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support/>
  <Project>https://caddyserver.com</Project>
  <Overview>Caddy web server with automatic HTTPS via Cloudflare DNS challenge. Serves static files and/or acts as reverse proxy for multiple subdomains.</Overview>
  <Category>Network:Web</Category>
  <WebUI>https://[IP]:[PORT:8443]/</WebUI>
  <TemplateURL/>
  <Icon>https://caddyserver.com/old/resources/images/caddy-logo.svg</Icon>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DateInstalled/>
  <DonateText/>
  <DonateLink/>
  <Requires/>

  <Config Name="HTTPS Port" Target="8443" Default="8443" Mode="tcp" Description="HTTPS port exposed on the host" Type="Port" Display="always" Required="true" Mask="false">8443</Config>

  <Config Name="HTTP Port" Target="8080" Default="8080" Mode="tcp" Description="HTTP port (redirects to HTTPS)" Type="Port" Display="always" Required="true" Mask="false">8080</Config>

  <Config Name="Cloudflare API Token" Target="CLOUDFLARE_API_TOKEN" Default="" Mode="" Description="Cloudflare API Token with Zone:DNS:Edit permission for your domain" Type="Variable" Display="always" Required="true" Mask="true"></Config>

  <Config Name="Static HTML folder" Target="/srv/www" Default="/mnt/user/appdata/caddy/www" Mode="ro" Description="Folder containing static HTML files. Mounted read-only for security." Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/caddy/www</Config>

  <Config Name="Caddyfile" Target="/etc/caddy/Caddyfile" Default="/mnt/user/appdata/caddy/Caddyfile" Mode="ro" Description="Path to your Caddyfile configuration on the host" Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/caddy/Caddyfile</Config>

  <Config Name="Caddy Data (certificates)" Target="/data" Default="/mnt/user/appdata/caddy/data" Mode="rw" Description="Persistent storage for TLS certificates. Do not delete." Type="Path" Display="advanced" Required="true" Mask="false">/mnt/user/appdata/caddy/data</Config>

  <Config Name="Caddy Config" Target="/config" Default="/mnt/user/appdata/caddy/config" Mode="rw" Description="Persistent storage for Caddy internal state" Type="Path" Display="advanced" Required="true" Mask="false">/mnt/user/appdata/caddy/config</Config>
</Container>
```

- [ ] **Step 2: Verify XML is well-formed**

```bash
xmllint --noout unraid-template.xml && echo "XML valid"
```
Expected: `XML valid`

If `xmllint` is not available:
```bash
python3 -c "import xml.etree.ElementTree as ET; ET.parse('unraid-template.xml'); print('XML valid')"
```

- [ ] **Step 3: Commit**

```bash
git add unraid-template.xml
git commit -m "feat: add Unraid Community Applications XML template"
```

---

### Task 5: Final validation

**Files:**
- No new files

- [ ] **Step 1: Verify all files are present**

```bash
ls -la
```
Expected files:
```
Dockerfile
Caddyfile.example
docker-compose.yml
unraid-template.xml
docs/superpowers/specs/2026-05-04-caddy-unraid-design.md
docs/superpowers/plans/2026-05-04-caddy-unraid.md
```

- [ ] **Step 3: Full rebuild and final smoke test (run from Unraid host — Docker required)**

```bash
docker build --no-cache -t caddy-cloudflare:latest .
docker run --rm caddy-cloudflare:latest caddy list-modules | grep cloudflare
docker run --rm caddy-cloudflare:latest caddy version
```
Expected: module `dns.providers.cloudflare` present, version matches `CADDY_VERSION` ARG.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete caddy-cloudflare Unraid Docker setup"
```
