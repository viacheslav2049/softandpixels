# syntax=docker/dockerfile:1.7
FROM caddy:2

RUN apk add --no-cache gettext bash

COPY proxy/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY Caddyfile.template /etc/caddy/Caddyfile.template

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 443
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
