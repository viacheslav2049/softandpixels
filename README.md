# softandpixels

A two-container stack that terminates HTTPS for one or many domains and routes
each one to a Sinatra + Puma application backend. The same config runs locally
(Caddy's internal CA) and on a public VPS (Let's Encrypt HTTP-01). Add more
upstream services later by appending to `DOMAIN_UPSTREAMS` in `.env`.

See [`docs/superpowers/specs/2026-06-07-caddy-sinatra-multi-domain-design.md`](docs/superpowers/specs/2026-06-07-caddy-sinatra-multi-domain-design.md)
for the design rationale.

## Dev — first time

```sh
cp .env.example .env
docker compose up -d --build
# One-time: trust the dev Caddy CA in the OS so browsers stop warning.
docker compose cp proxy:/data/caddy/pki/authorities/local/root.crt ./dev-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./dev-ca.crt   # macOS
# Linux (Debian/Ubuntu):
# sudo cp ./dev-ca.crt /usr/local/share/ca-certificates/caddy-dev.crt && sudo update-ca-certificates
open https://example.localhost
```

## Dev — regular

```sh
docker compose up -d --build
docker compose logs -f
```

## Prod — first time on a VPS

```sh
cp .env.example .env
# Edit .env:
#   CADDY_ENV=prod
#   LETSENCRYPT_EMAIL=<your real email>
#   DOMAIN_UPSTREAMS=<your real domains mapped to upstream:port>
# Ensure DNS A/AAAA records for each domain point to the VPS public IP.
# Ensure the firewall allows inbound TCP 80 and 443.
docker compose up -d --build
```

## Adding a new upstream service

1. Add a new `services:` block in `docker-compose.yml` on the `web` network, with `expose: ["PORT"]`.
2. Append `newdomain=service:PORT` to `DOMAIN_UPSTREAMS` in `.env`.
3. `docker compose up -d`.

Caddy picks up the new domain on restart.

## Running the Sinatra tests

```sh
cd app && bundle install && bundle exec rspec
```

## Layout

```
.
├── Caddyfile.template         # rendered to Caddyfile at proxy container start
├── docker-compose.yml
├── .env.example
├── proxy/
│   ├── Dockerfile
│   └── entrypoint.sh          # the Caddyfile renderer
└── app/
    ├── Dockerfile
    ├── Gemfile
    ├── app.rb
    ├── config.ru
    ├── public/                # index.html, styles.css, app.js
    └── spec/                  # rspec tests for the Sinatra app
```
