# Caddy + Sinatra Multi-Domain Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a two-container stack (Caddy reverse proxy in front, Sinatra + Puma app behind) that terminates HTTPS for multiple domains, auto-provisions certificates, and routes each domain to a configurable upstream — works identically on a developer's laptop (Caddy's internal CA) and on a public VPS (Let's Encrypt HTTP-01).

**Architecture:** One Docker Compose project with two services. The `proxy` service runs Caddy 2 with a template-rendered Caddyfile (envsubst + awk spliced placeholders) and persists certs/ACME state on named volumes. The `app` service runs Sinatra 4 on Ruby 3.3.6 via Puma, serving static assets from a `public/` directory, and is reachable only on the internal `web` Docker network. A `.env` file drives the per-domain routing and dev/prod SSL switch.

**Tech Stack:** Caddy 2, Docker Compose v2, Alpine (proxy base), Ruby 3.3.6-slim, Sinatra 4, Puma 6, RSpec 3, Rack::Test, Bash, envsubst, awk.

**Reference spec:** `docs/superpowers/specs/2026-06-07-caddy-sinatra-multi-domain-design.md`

---

## Task 1: Sinatra Gemfile with TDD-ready test gems

**Files:**
- Create: `app/Gemfile`

- [ ] **Step 1: Create the Gemfile**

Write `app/Gemfile`:

```ruby
source "https://rubygems.org"

ruby "3.3.6"

gem "sinatra", "~> 4.0"
gem "puma",    "~> 6.4"
gem "rackup",  "~> 2.1"

group :test do
  gem "rspec",     "~> 3.13"
  gem "rack-test", "~> 2.1"
end
```

- [ ] **Step 2: Run bundle install to verify the Gemfile resolves**

Run from the project root:
```sh
cd app && bundle install
```

Expected: ends with `Bundle complete! 4 Gemfile dependencies, X gems now installed.` No version conflicts.

- [ ] **Step 3: Commit**

```sh
cd .. && git add app/Gemfile app/Gemfile.lock && git commit -m "Add Sinatra app Gemfile with TDD-ready test gems"
```

---

## Task 2: Sinatra app with TDD (red → green)

**Files:**
- Create: `app/app.rb`
- Create: `app/config.ru`
- Create: `app/spec/spec_helper.rb`
- Create: `app/spec/app_spec.rb`
- Create: `app/public/index.html`
- Create: `app/public/styles.css`
- Create: `app/public/app.js`
- Create: `app/.rspec`

- [ ] **Step 1: Create `.rspec` config**

Write `app/.rspec`:
```
--require spec_helper
--format documentation
--color
```

- [ ] **Step 2: Create `spec/spec_helper.rb`**

Write `app/spec/spec_helper.rb`:

```ruby
require "rspec"
require "rack/test"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.include Rack::Test::Methods
end
```

- [ ] **Step 3: Write the failing spec for `/` and `/_health`**

Write `app/spec/app_spec.rb`:

```ruby
require_relative "../app"

RSpec.describe Sinatra::Application do
  def app
    Sinatra::Application
  end

  describe "GET /_health" do
    it "returns 200 with body 'ok'" do
      get "/_health"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("ok")
    end
  end

  describe "GET /" do
    it "returns 200 and serves index.html" do
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Hello from Sinatra")
    end
  end

  describe "GET /styles.css" do
    it "returns 200 with CSS content type" do
      get "/styles.css"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("text/css")
      expect(last_response.body.strip).not_to be_empty
    end
  end

  describe "GET /app.js" do
    it "returns 200 with JS content type" do
      get "/app.js"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("javascript")
      expect(last_response.body.strip).not_to be_empty
    end
  end

  describe "GET /does-not-exist" do
    it "returns 404" do
      get "/does-not-exist"
      expect(last_response.status).to eq(404)
    end
  end
end
```

- [ ] **Step 4: Create minimal `public/` assets so the static file tests can pass**

Write `app/public/index.html`:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Hello from Sinatra</title>
    <link rel="stylesheet" href="/styles.css" />
  </head>
  <body>
    <h1>Hello from Sinatra</h1>
    <p>Placeholder content — replace with your own.</p>
    <script src="/app.js"></script>
  </body>
</html>
```

Write `app/public/styles.css`:
```css
body {
  font-family: system-ui, sans-serif;
  margin: 2rem;
  color: #222;
}
h1 { color: #2a6df4; }
```

Write `app/public/app.js`:
```javascript
console.log("app.js loaded");
```

- [ ] **Step 5: Create a partial `app.rb` (only static-serving) to confirm the tests fail (RED)**

Write `app/app.rb`:
```ruby
require "sinatra"

set :public_folder, File.expand_path("public", __dir__)
```

NOTE: With just this stub, `Rack::Test` requests will return 403, not 200, because **Sinatra 4 enables `host_authorization` by default**, and `Rack::Test` doesn't set a permitted Host header. This is the RED state — every test in Step 6 fails. The Step 7 implementation disables `host_authorization` to make them pass.

- [ ] **Step 6: Run rspec, expect RED**

Run from the project root:
```sh
cd app && bundle exec rspec
```

Expected output (all 5 tests fail with 403 because `host_authorization` blocks every request until Step 7 disables it):
```
Failures:

  1) Sinatra::Application GET /_health returns 200 with body 'ok'
     Failure/Error: expect(last_response.status).to eq(200)

       expected: 200
            got: 403
  ... (similar for the other 4 tests)

Finished in 0.05 seconds (files took 0.1 seconds to load)
5 examples, 5 failures
```

If you see a mix of 200/404 (some passing), something is wrong — STOP and re-check the stub in Step 5. The expected intermediate state is that NO tests pass yet.

- [ ] **Step 7: Implement `app.rb` to make all tests pass (GREEN)**

Replace `app/app.rb` with:

```ruby
require "sinatra"

set :public_folder, File.expand_path("public", __dir__)
set :host_authorization, { permitted_hosts: [] }
disable :protection
set :show_exceptions, false
set :raise_errors, false

get "/_health" do
  "ok"
end

get "/" do
  send_file File.join(settings.public_folder, "index.html")
end
```

Note 1: we do NOT set `:bind` or `:port` in `app.rb` because the app is run under Puma in production; Puma reads `PORT` from the environment directly, and Sinatra's `:port`/`:bind` settings are ignored by Puma.

Note 2: Sinatra 4's `static!` method (serving `public_folder` files) does **not** auto-serve `public/index.html` at `/` — it only serves exact-path matches like `/styles.css`. That's why the explicit `get "/"` route is required.

- [ ] **Step 8: Run rspec, expect GREEN**

Run:
```sh
cd app && bundle exec rspec
```

Expected:
```
5 examples, 0 failures
```

- [ ] **Step 9: Add `config.ru`**

Write `app/config.ru`:
```ruby
require_relative "app"
run Sinatra::Application
```

- [ ] **Step 10: Smoke-test with rackup**

Run from `app/`:
```sh
cd app && bundle exec rackup -p 4567 -o 0.0.0.0 &
SERVER_PID=$!
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4567/_health   # expect: 200
curl -s http://localhost:4567/ | grep -q "Hello from Sinatra" && echo OK   # expect: OK
kill $SERVER_PID
```

Expected: `200` and `OK`.

- [ ] **Step 11: Commit**

```sh
cd .. && git add app/app.rb app/config.ru app/public app/spec app/.rspec && git commit -m "Add Sinatra app with TDD-covered /_health and static-asset routes"
```

---

## Task 3: Sinatra app Dockerfile

**Files:**
- Create: `app/Dockerfile`
- Create: `app/.dockerignore`

- [ ] **Step 1: Create `app/.dockerignore`**

Write `app/.dockerignore`:
```
.git
.gitignore
spec
.rspec
*.log
log
tmp
.env*
dev-ca.crt
```

This keeps the test group gems and the spec directory out of the runtime image.

- [ ] **Step 2: Create `app/Dockerfile`**

Write `app/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.7

FROM ruby:3.3.6-slim AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libyaml-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4

FROM ruby:3.3.6-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 app \
    && useradd  --system --uid 1000 --gid 1000 --no-create-home app
WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . /app
USER app
ENV PORT=4567
EXPOSE 4567
HEALTHCHECK CMD ruby -rsocket -e 'TCPSocket.new("127.0.0.1",ENV["PORT"]).close'
CMD ["bundle", "exec", "puma"]
```

- [ ] **Step 3: Build the app image**

Run from the project root:
```sh
docker build -t softandpixels/app:test ./app
```

Expected: ends with `Successfully tagged softandpixels/app:test`.

- [ ] **Step 4: Run the container and verify the health endpoint**

```sh
docker run -d --name app-test -p 4567:4567 softandpixels/app:test
sleep 3
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4567/_health   # expect: 200
curl -s http://localhost:4567/ | grep -q "Hello from Sinatra" && echo OK   # expect: OK
docker logs app-test 2>&1 | tail -20
docker stop app-test && docker rm app-test
```

Expected: `200`, `OK`, and Puma startup logs visible in `docker logs`.

- [ ] **Step 5: Commit**

```sh
git add app/Dockerfile app/.dockerignore && git commit -m "Add multi-stage Dockerfile for Sinatra app"
```

---

## Task 4: Caddyfile template (the static part)

**Files:**
- Create: `Caddyfile.template` (top-level)

- [ ] **Step 1: Create the template**

Write `Caddyfile.template`:

```
{
	email {$LETSENCRYPT_EMAIL}
	{$CADDY_GLOBAL_OPTIONS}
}
__PER_DOMAIN_BLOCKS__
__DEV_WILDCARD_BLOCK__
__PROD_HTTP_REDIRECT__
```

The placeholders `__PER_DOMAIN_BLOCKS__`, `__DEV_WILDCARD_BLOCK__`, and `__PROD_HTTP_REDIRECT__` are replaced with multi-line Caddy text by `proxy/entrypoint.sh` (Task 5). The `{$VAR}` placeholders are replaced by `envsubst` at the end of the entrypoint.

- [ ] **Step 2: Commit**

```sh
git add Caddyfile.template && git commit -m "Add Caddyfile template with placeholders for envsubst + awk splicing"
```

---

## Task 5: Caddy entrypoint script (renders the Caddyfile from .env)

**Files:**
- Create: `proxy/entrypoint.sh`

- [ ] **Step 1: Create the entrypoint script**

Write `proxy/entrypoint.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ---------- Validate inputs ----------
: "${CADDY_ENV:?CADDY_ENV must be set to 'dev' or 'prod'}"
: "${DOMAIN_UPSTREAMS:?DOMAIN_UPSTREAMS must be set, e.g. example.com=app:4567}"
case "$CADDY_ENV" in
  dev|prod) ;;
  *) echo "CADDY_ENV must be 'dev' or 'prod', got: '$CADDY_ENV'" >&2; exit 1 ;;
esac

TEMPLATE=/etc/caddy/Caddyfile.template
OUT=/etc/caddy/Caddyfile
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ---------- Build per-domain blocks ----------
: > "$TMPDIR/per_domain"
IFS=',' read -ra PAIRS <<< "$DOMAIN_UPSTREAMS"
for pair in "${PAIRS[@]}"; do
  domain="${pair%%=*}"
  upstream="${pair#*=}"
  if [[ "$domain" == "$pair" || -z "$upstream" ]]; then
    echo "Bad DOMAIN_UPSTREAMS entry: '$pair' (expected host=upstream:port)" >&2
    exit 1
  fi
  if [[ "$CADDY_ENV" == "dev" ]]; then
    cat >> "$TMPDIR/per_domain" <<EOF

${domain} {
    tls internal
    reverse_proxy ${upstream}
    encode gzip zstd
}
EOF
  else
    cat >> "$TMPDIR/per_domain" <<EOF

${domain} {
    reverse_proxy ${upstream}
    encode gzip zstd
}
EOF
  fi
done

# ---------- Dev-only wildcard block / prod-only :80 redirect ----------
: > "$TMPDIR/dev_wildcard"
: > "$TMPDIR/prod_redirect"
if [[ "$CADDY_ENV" == "dev" ]]; then
  cat > "$TMPDIR/dev_wildcard" <<EOF

*.localhost, localhost {
    tls internal
    reverse_proxy ${DEV_DEFAULT_UPSTREAM:-app:4567}
}
EOF
else
  cat > "$TMPDIR/prod_redirect" <<'EOF'

:80 {
    redir https://{host}{uri} permanent
}
EOF
fi

# ---------- Splice placeholders into the template ----------
awk \
  -v pdb="$TMPDIR/per_domain" \
  -v dwb="$TMPDIR/dev_wildcard" \
  -v phr="$TMPDIR/prod_redirect" '
  function read_file(path,    line, content) {
    content = ""
    while ((getline line < path) > 0) content = content line "\n"
    close(path)
    return content
  }
  BEGIN {
    pdb_content = read_file(pdb)
    dwb_content = read_file(dwb)
    phr_content = read_file(phr)
  }
  {
    line = $0
    sub(/__PER_DOMAIN_BLOCKS__/, pdb_content, line)
    sub(/__DEV_WILDCARD_BLOCK__/, dwb_content, line)
    sub(/__PROD_HTTP_REDIRECT__/, phr_content, line)
    print line
  }
' "$TEMPLATE" > "$OUT"

# ---------- envsubst for {$VAR} placeholders ----------
envsubst < "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

# ---------- Debug ----------
echo "===== Rendered Caddyfile ====="
cat "$OUT"
echo "=============================="

# ---------- Hand off to Caddy ----------
exec caddy run --config "$OUT"
```

- [ ] **Step 2: Commit**

```sh
git add proxy/entrypoint.sh && git commit -m "Add Caddy entrypoint that renders Caddyfile.template from env"
```

Note: the file is executable in the working tree (the commit preserves mode). On systems where `git config core.fileMode` is `false`, the executable bit will be restored from the index by `git checkout`. If the bit is lost in clone, run `chmod +x proxy/entrypoint.sh` — but the Dockerfile also explicitly `chmod`s it, so this is belt-and-braces.

---

## Task 6: Caddy Dockerfile and standalone smoke test

**Files:**
- Create: `proxy/Dockerfile`

- [ ] **Step 1: Create the Dockerfile**

Write `proxy/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM caddy:2

RUN apk add --no-cache gettext bash

COPY proxy/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY Caddyfile.template /etc/caddy/Caddyfile.template

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 443
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

The Dockerfile is committed at `proxy/Dockerfile`, but the build context is the project root (so paths inside `COPY` are relative to the project root, not the Dockerfile's directory). This is the standard pattern for monorepo Dockerfiles that reference files outside the Dockerfile's own folder.

- [ ] **Step 2: Build the proxy image from the project root**

Run from the project root:
```sh
docker build -t softandpixels/proxy:test -f proxy/Dockerfile .
```

Expected: ends with `Successfully tagged softandpixels/proxy:test`.

- [ ] **Step 3: Run the proxy container and verify Caddyfile rendering**

```sh
docker run -d --name proxy-test \
  -p 80:80 -p 443:443 \
  -e CADDY_ENV=dev \
  -e LETSENCRYPT_EMAIL=test@example.com \
  -e DOMAIN_UPSTREAMS=example.test=app:4567 \
  softandpixels/proxy:test
sleep 3
docker exec proxy-test cat /etc/caddy/Caddyfile
docker exec proxy-test ls /data/caddy/pki/authorities/local/   # expect: root.crt (dev CA generated)
docker logs proxy-test 2>&1 | head -40
docker stop proxy-test && docker rm proxy-test
```

Expected: the rendered Caddyfile contains an `example.test` block with `tls internal` and `reverse_proxy app:4567`, plus the `*.localhost, localhost` wildcard block. Caddy logs show `serving HTTPS on :443`.

- [ ] **Step 4: Commit**

```sh
git add proxy/Dockerfile && git commit -m "Add Caddy proxy Dockerfile and verify dev config renders"
```

---

## Task 7: docker-compose.yml + .env.example

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`

- [ ] **Step 1: Create `.env.example`**

Write `.env.example`:

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

- [ ] **Step 2: Create `docker-compose.yml`**

Write `docker-compose.yml`:

```yaml
services:
  proxy:
    image: softandpixels/proxy:latest
    build:
      context: .
      dockerfile: proxy/Dockerfile
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
    image: softandpixels/app:latest
    build: ./app
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

- [ ] **Step 3: Create a local `.env` from the example**

```sh
cp .env.example .env
```

Verify `.gitignore` already excludes `.env`:
```sh
grep -E '^\.env$' .gitignore
```

Expected: a line containing `.env`.

- [ ] **Step 4: Bring the stack up**

```sh
docker compose up -d --build
```

Expected output ends with:
```
Container softandpixels-app-1     Healthy
Container softandpixels-proxy-1  Started
```

If your project directory has a different compose project name, the container prefixes will differ — that's fine.

- [ ] **Step 5: Verify both services are healthy and the routing works**

```sh
docker compose ps
curl -kI https://example.localhost/_health   # expect: HTTP/2 200
curl -kI https://example.localhost/          # expect: HTTP/2 200
curl -ks https://example.localhost/ | grep -q "Hello from Sinatra" && echo OK   # expect: OK
curl -kI https://beta.example.localhost/     # expect: HTTP/2 200
```

If any of the 200s come back as 502, give Caddy a few more seconds to start, then re-check: `docker compose logs proxy`.

- [ ] **Step 6: Inspect Caddy's logs to confirm the CA path**

```sh
docker compose logs proxy | head -30
docker compose exec proxy ls /data/caddy/pki/authorities/local/   # expect: root.crt
docker compose exec proxy cat /etc/caddy/Caddyfile                # expect: rendered config
```

- [ ] **Step 7: Commit**

```sh
git add docker-compose.yml .env.example && git commit -m "Add docker-compose stack and .env.example; verified dev routing"
```

---

## Task 8: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Write `README.md`:

````markdown
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
````

- [ ] **Step 2: Commit**

```sh
git add README.md && git commit -m "Add README with dev/prod workflows and pluggability notes"
```

---

## Task 9: End-to-end verification

**Files:** (no new files; this task is verification only)

- [ ] **Step 1: Verify the dev CA trust flow**

After Task 7, with the dev CA installed in the OS keychain (Task 8 first-time setup), open `https://example.localhost` in a browser and confirm there is no certificate warning.

Expected: the page loads over HTTPS without warnings; the lock icon is closed/padlocked.

- [ ] **Step 2: Verify pluggability — add a third domain without rebuilding the app image**

```sh
# In .env, append a new mapping that points to the same app:
# DOMAIN_UPSTREAMS=example.localhost=app:4567,beta.example.localhost=app:4567,gamma.example.localhost=app:4567
docker compose up -d proxy
curl -kI https://gamma.example.localhost/   # expect: HTTP/2 200
```

- [ ] **Step 3: Run the Sinatra test suite once more**

```sh
cd app && bundle exec rspec
```

Expected: `5 examples, 0 failures`.

- [ ] **Step 4: Take the stack down cleanly (preserving the Caddy volumes)**

```sh
docker compose down
```

Volumes `caddy_data` and `caddy_config` are preserved (no `-v` flag). A subsequent `docker compose up -d` will reuse the existing dev CA and any prod ACME state.

- [ ] **Step 5: Commit any final adjustments (e.g. README corrections)**

```sh
git status
# If anything is dirty:
git add -A && git commit -m "Final adjustments from end-to-end verification"
```

Expected: clean working tree, all changes committed.

---

## Done criteria

- [ ] All 9 tasks complete; working tree clean.
- [ ] `docker compose up -d --build` brings both services up healthy.
- [ ] `https://example.localhost/` returns 200 with "Hello from Sinatra" in the body.
- [ ] `cd app && bundle exec rspec` → 5 examples, 0 failures.
- [ ] Caddy's dev CA is generated under the `caddy_data` volume; trusting it in the host OS removes all browser warnings.
- [ ] README is current and accurate.
