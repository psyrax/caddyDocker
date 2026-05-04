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
