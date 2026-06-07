# Multi-Domain Caddy + Sinatra Stack (Design Spec)

**Date:** 2026-06-07
**Status:** Approved (brainstorming), pending written-spec review
**Project root:** `/Users/viacheslavkozlov/dev/PROJECTS/softandpixels`

---

## 1. Goal

Provide a small, reproducible two-container stack that:

1. Terminates HTTPS for one or many domains, automatically provisioning certificates.
2. Routes every request to a Sinatra application backend (with the option to add more backend services later).
3. Runs identically on a developer's laptop and on a public VPS, with the only differences being environment variables.

The Sinatra app is a tiny static-asset host (HTML + CSS + JS), served by Sinatra on Ruby 3.3.6 via Puma, declared as the spec's required framework.

---

## 2. Architecture

```
                        Internet
                           │
                ┌──────────┴──────────┐
                │  Host (laptop /     │
                │  VPS)               │
                │  :80   :443         │
                └──────────┬──────────┘
                           │  published ports
                ┌──────────┴──────────┐
                │   proxy (caddy)     │  ── /data  (caddy_data)   ← certs & ACME account
                │   Caddy 2           │  ── /config(caddy_config) ← Caddy's runtime state
                │   :80  :443         │  ── /etc/caddy/Caddyfile  (rendered at start)
                └──────────┬──────────┘
                           │  on internal Docker network `web`
                ┌──────────┴──────────┐
                │   app (sinatra)     │  ── /app/public  (static assets)
                │   Ruby 3.3.6 + Puma │
                │   :4567 (internal)  │  ← NOT published to host
                └─────────────────────┘
```

**Topology rules:**

- One Docker bridge network `web` shared by both services. Caddy reaches the app by service name (`http://app:4567`).
- Only the `proxy` service publishes host ports (`80`, `443`). The `app` service is reachable only from inside the Docker network; it is never exposed directly to the host.
- Caddy's state is on two named volumes (`caddy_data`, `caddy_config`). In dev these hold the auto-generated internal CA and its leaf certificates. In prod they hold the Let's Encrypt account and per-domain certificates. Containers can be recreated without losing certs.
- "Pluggable" routing: adding a new upstream application later = add a new service to `docker-compose.yml` on the `web` network, and add a `reverse_proxy newapp:PORT` block for the relevant domain(s) in the Caddyfile template. No other architectural changes are required.

---

## 3. Components

### 3.1 Project layout

```
softandpixels/
├── docker-compose.yml
├── Caddyfile.template
├── .env.example
├── .gitignore
├── README.md
├── proxy/
│   ├── Dockerfile
│   └── entrypoint.sh
└── app/
    ├── Dockerfile
    ├── Gemfile
    ├── config.ru
    ├── app.rb
    └── public/
        ├── index.html
        ├── styles.css
        └── app.js
```

### 3.2 `proxy` container (Caddy 2)

**Image base:** `caddy:2` (official), with a small custom Dockerfile that adds an `entrypoint.sh`.

**`proxy/Dockerfile`:**
- `FROM caddy:2`
- `RUN apk add --no-cache gettext bash` (adds `envsubst` and `bash`; the base `caddy:2` image is Alpine-based and ships with `ash`, but `bash` is cleaner for the entrypoint script).
- Copy `entrypoint.sh` to `/usr/local/bin/entrypoint.sh`, mark executable.
- Copy `Caddyfile.template` to `/etc/caddy/Caddyfile.template` (read-only).
- `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`
- `CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]`
- `EXPOSE 80 443`

**`proxy/entrypoint.sh`:** A `bash` script that:
1. Asserts that `CADDY_ENV` is `dev` or `prod` and `DOMAIN_UPSTREAMS` is non-empty; prints a clear error and exits non-zero otherwise.
2. Performs the substitutions described in section 4.1.
3. Renders the final Caddyfile to `/etc/caddy/Caddyfile`.
4. Execs `caddy run --config /etc/caddy/Caddyfile` (overriding the `CMD`).

**Volumes (mounted on the proxy container):**
- `caddy_data:/data` — ACME account (prod) and internal CA + leaf certs (dev).
- `caddy_config:/config` — Caddy's runtime state.

**Environment variables consumed:**
- `CADDY_ENV` — `dev` (default) or `prod`.
- `LETSENCRYPT_EMAIL` — required in prod, ignored in dev.
- `DOMAIN_UPSTREAMS` — comma-separated list of `host=upstream:port` pairs.

### 3.3 `app` container (Sinatra + Puma + Ruby 3.3.6)

**`app/Gemfile`:**
```ruby
source "https://rubygems.org"
ruby "3.3.6"
gem "sinatra", "~> 4.0"
gem "puma",    "~> 6.4"
gem "rackup",  "~> 2.1"
```

**`app/config.ru`:**
```ruby
require_relative "app"
run Sinatra::Application
```

**`app/app.rb`:** A Sinatra application that:
1. Disables host authorization (Caddy is the only thing that can reach it; we accept any host).
2. Sets `set :public_folder, File.expand_path("public", __dir__)` to serve `index.html`, `styles.css`, `app.js` directly.
3. Logs to STDOUT in a `Common Log Format`-style line per request so `docker compose logs app` is readable.
4. Exposes a health endpoint:
   ```ruby
   get "/_health" do
     "ok"
   end
   ```
5. Falls through to a 404 (Sinatra's default) for anything not found in `public/`.

**`app/Dockerfile`** — multi-stage, slim:
- **Stage 1 `builder`:**
  - `FROM ruby:3.3.6-slim`
  - `RUN apt-get update && apt-get install -y --no-install-recommends build-essential libyaml-dev && rm -rf /var/lib/apt/lists/*`
  - `WORKDIR /app`
  - `COPY Gemfile Gemfile.lock* ./`  (Gemfile.lock is allowed to be missing on first build)
  - `RUN bundle config set --local without 'development test' && bundle install --jobs 4`
- **Stage 2 (final):**
  - `FROM ruby:3.3.6-slim`
  - `RUN apt-get update && apt-get install -y --no-install-recommends libyaml-0-2 && rm -rf /var/lib/apt/lists/*` and create a non-root user `app` (uid 1000).
  - `COPY --from=builder /usr/local/bundle /usr/local/bundle`
  - `WORKDIR /app`
  - `COPY --chown=app:app . /app`
  - `USER app`
  - `EXPOSE 4567`
  - `ENV PORT=4567`
  - `HEALTHCHECK CMD ruby -rsocket -e 'TCPSocket.new("127.0.0.1",ENV["PORT"]).close'`
  - `CMD ["bundle", "exec", "puma", "-C", "-"]` with a piped inline `puma` config: `port (ENV['PORT']||4567).to_i; threads 1, 5; workers 0`.

**`app/public/`:** The actual user content. The repo ships a minimal "Hello from Sinatra" `index.html` + tiny `styles.css` + tiny `app.js` so a fresh clone is end-to-end testable. The user replaces these with their real content.

### 3.4 Networking

- Single user-defined bridge network `web` declared in `docker-compose.yml`.
- Service names are the DNS names. Caddy's `reverse_proxy app:4567` resolves through this network.
- No host network mode, no extra networks.

### 3.5 Volumes

- `caddy_data` and `caddy_config` are named volumes (defined in the `volumes:` block of `docker-compose.yml`).
- The Sinatra app uses no persistent volumes — static assets are baked into the image.

---

## 4. Configuration

### 4.1 `Caddyfile.template`

The committed template (`Caddyfile.template`, top-level) is a small file with three substitution points. All heavy lifting is done in `proxy/entrypoint.sh`:

```
{
	email {$LETSENCRYPT_EMAIL}
	{$CADDY_GLOBAL_OPTIONS}
}
__PER_DOMAIN_BLOCKS__
__DEV_WILDCARD_BLOCK__
__PROD_HTTP_REDIRECT__
```

Substitution conventions:
- `{$VAR}` is replaced by `envsubst` at run-time. `envsubst` comes from the `gettext` package; the proxy Dockerfile installs it explicitly (see below).
- `__PLACEHOLDER__` markers are entire block-of-Caddyfile-text substitutions performed by the entrypoint script (writing each block to a temp file and using `awk` or `sed` to splice it in). They are intentionally NOT simple `{$VAR}` substitutions because their values are multi-line.

**Render-time logic in `entrypoint.sh`:**

1. Parse `DOMAIN_UPSTREAMS` (e.g. `example.com=app:4567,beta.example.com=app:4567`) into a list of `host=upstream:port` pairs. Reject the start with a clear error if the variable is unset or malformed.
2. If `CADDY_ENV=dev`:
   - `__PER_DOMAIN_BLOCKS__` becomes, for each pair:
     ```
     <host1>, <host2>, ... {
         tls internal
         reverse_proxy <upstream:port>
         encode gzip zstd
     }
     ```
   - `__DEV_WILDCARD_BLOCK__` becomes:
     ```
     *.localhost, localhost {
         tls internal
         reverse_proxy {$DEV_DEFAULT_UPSTREAM:-app:4567}
     }
     ```
   - `__PROD_HTTP_REDIRECT__` becomes empty.
   - `CADDY_GLOBAL_OPTIONS` becomes:
     ```
     admin off
     acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
     ```
     The staging CA is a safety net: per-domain blocks use `tls internal`, so Let's Encrypt is never actually contacted in dev. If a future dev block accidentally omits `tls internal`, the staging CA prevents rate-limiting the real production CA.
3. If `CADDY_ENV=prod`:
   - `__PER_DOMAIN_BLOCKS__` becomes, for each pair:
     ```
     <host1>, <host2>, ... {
         reverse_proxy <upstream:port>
         encode gzip zstd
     }
     ```
     (No explicit `tls` directive — Caddy auto-uses Let's Encrypt because the global `email` is set and port 80 is reachable.)
   - `__PROD_HTTP_REDIRECT__` becomes a single global block:
     ```
     :80 {
         redir https://{host}{uri} permanent
     }
     ```
   - `__DEV_WILDCARD_BLOCK__` becomes empty.
   - `CADDY_GLOBAL_OPTIONS` is unset (empty string).

The final rendered Caddyfile is written to `/etc/caddy/Caddyfile` and the entrypoint execs `caddy run --config /etc/caddy/Caddyfile`. Caddy validates the config on startup; on syntax error the entrypoint exits non-zero and `docker compose up` fails loudly.

### 4.2 `.env.example` (committed)

```dotenv
# dev | prod
CADDY_ENV=dev

# Required in prod, ignored in dev
LETSENCRYPT_EMAIL=you@example.com

# Comma-separated list of host=upstream:port pairs.
# Dev example:
DOMAIN_UPSTREAMS=example.localhost=app:4567,beta.example.localhost=app:4567
# Prod example:
# DOMAIN_UPSTREAMS=example.com=app:4567,www.example.com=app:4567,api.example.com=app:4567

# Used only in dev's wildcard catch-all block; defaults to app:4567
# DEV_DEFAULT_UPSTREAM=app:4567

# Sinatra
RACK_ENV=production
PORT=4567
```

`.env` is git-ignored; `.env.example` is committed.

### 4.3 `docker-compose.yml`

```yaml
services:
  proxy:
    build: ./proxy
    image: softandpixels/proxy:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      CADDY_ENV: ${CADDY_ENV:-dev}
      LETSENCRYPT_EMAIL: ${LETSENCRYPT_EMAIL:-}
      DOMAIN_UPSTREAMS: ${DOMAIN_UPSTREAMS}
      DEV_DEFAULT_UPSTREAM: ${DEV_DEFAULT_UPSTREAM:-app:4567}
    volumes:
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      app:
        condition: service_healthy
    networks: [web]

  app:
    build: ./app
    image: softandpixels/app:latest
    restart: unless-stopped
    expose:
      - "4567"
    environment:
      PORT: "4567"
      RACK_ENV: ${RACK_ENV:-production}
    healthcheck:
      test: ["CMD-SHELL", "ruby -rsocket -e 'TCPSocket.new(\"127.0.0.1\",ENV[\"PORT\"]).close'"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks: [web]

volumes:
  caddy_data:
  caddy_config:

networks:
  web:
    driver: bridge
```

---

## 5. Build & run flows

### 5.1 First-time dev setup

```sh
cp .env.example .env
docker compose up -d --build                   # start the stack; Caddy generates its internal CA inside the proxy container
docker compose cp proxy:/data/caddy/pki/authorities/local/root.crt ./dev-ca.crt

# macOS: install the dev CA into the System keychain (one-time)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./dev-ca.crt

# Linux (Debian/Ubuntu): copy into the system CA bundle and refresh
sudo cp ./dev-ca.crt /usr/local/share/ca-certificates/caddy-dev.crt
sudo update-ca-certificates

# Firefox (if it uses its own cert store, not the system one): Preferences → Privacy & Security →
# Certificates → View Certificates → Authorities → Import… → select ./dev-ca.crt → Trust this CA to identify websites.
```

Expected: browser shows the placeholder `index.html` over HTTPS at `https://example.localhost` with no certificate warnings.

The internal CA persists in the `caddy_data` named volume, so this one-time trust step only needs to be repeated if the volume is deleted (e.g. `docker compose down -v`). If you only need to script/curl the dev service, `curl -k` is acceptable instead of installing the CA.

### 5.2 Regular dev

```sh
docker compose up -d --build
docker compose logs -f
```

### 5.3 First-time prod (VPS)

```sh
cp .env.example .env
# Edit .env: CADDY_ENV=prod, real domains in DOMAIN_UPSTREAMS, real LETSENCRYPT_EMAIL
# Ensure DNS A/AAAA records point each domain to the VPS public IP.
# Ensure firewall allows inbound TCP 80 and 443.
docker compose up -d --build
```

Expected: `https://<your-domain>/` returns the placeholder page; Caddy logs show ACME account creation and certificate issuance.

### 5.4 Regular prod

```sh
docker compose pull        # if/once images are pushed to a registry
docker compose up -d
```

(For the initial version, images are built on the VPS itself; a registry is out of scope.)

### 5.5 Adding a new backend app later (pluggability)

1. Add a new service in `docker-compose.yml`, e.g. `api:`, with `expose: ["3000"]` and `networks: [web]`.
2. Add a mapping to `DOMAIN_UPSTREAMS` in `.env`, e.g. `api.example.com=api:3000`.
3. `docker compose up -d`.

Caddy picks up the new domain on restart (or on `docker compose restart proxy`).

---

## 6. Testing approach

| Layer | Test | Required? |
|---|---|---|
| Sinatra | `GET /_health` returns `200 ok` (manual `curl` or one optional RSpec test) | Optional in v1 |
| Sinatra | `GET /` returns the `public/index.html` body | Manual verification |
| Caddy | `curl -kI https://<domain>/_health` returns `200` | Manual verification |
| Caddy | Dev: `curl -kI https://example.localhost/` returns 200 with no `acme` activity in logs | Manual verification |
| Caddy | Prod: `curl -I https://<domain>/` returns 200 with `200 OK` from Let's Encrypt cert | Manual verification |
| E2E | `curl -fsSL https://<domain>/` returns HTML containing a known string from `public/index.html` | Manual verification |

No CI pipeline in v1 (out of scope). All testing is local + post-deploy.

---

## 7. Out of scope (YAGNI)

- CI/CD pipelines, GitHub Actions, automated image push.
- Ansible / Terraform for the VPS.
- Wildcard certificates (DNS-01). Per-domain HTTP-01 is sufficient.
- Live Caddyfile reloads via Caddy's admin API (e.g. for zero-downtime domain adds). A `docker compose restart proxy` is acceptable.
- A container image registry. In v1, prod builds images on the VPS itself.
- Rate limiting, WAF, fail2ban, log shipping.
- Multi-tenant Sinatra behavior (per-host content variation) — the spec only needs static assets for now; multi-tenant is easy to add later inside `app.rb`.
- Custom auth, sessions, databases. Pure static page.

---

## 8. Decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Reverse proxy | Caddy 2 |
| 2 | Application framework | Sinatra 4 on Ruby 3.3.6, served by Puma |
| 3 | Routing model | Pluggable: per-domain `reverse_proxy host:port` to upstream services |
| 4 | Dev SSL | Caddy's `internal` CA (trusted in the host via `caddy trust`) |
| 5 | Prod SSL | Let's Encrypt HTTP-01 (Caddy's default once `email` is set) |
| 6 | Project layout | Two folders (`proxy/`, `app/`) + top-level `docker-compose.yml` + `.env` |
| 7 | Config strategy | `Caddyfile.template` rendered at container start from `.env` |
| 8 | Orchestration | docker compose v2 (single file for dev and prod) |
| 9 | Image building | Local builds (no registry) in v1 |
| 10 | Caddy state storage | Named volumes `caddy_data` + `caddy_config` |

---

## 9. Open questions

None at design time. All brainstorming questions were resolved.
