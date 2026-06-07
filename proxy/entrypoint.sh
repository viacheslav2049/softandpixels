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
