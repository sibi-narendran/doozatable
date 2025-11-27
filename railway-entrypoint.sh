#!/bin/bash

# Set Caddy address to the Railway PORT with explicit HTTP protocol
export BASEROW_CADDY_ADDRESSES="http://0.0.0.0:${PORT:-80}"

# Set Public URL:
# 1. Respect explicit BASEROW_PUBLIC_URL env var if set (e.g. via Railway Dashboard)
# 2. Fallback to Railway's auto-generated domain
# 3. Fallback to localhost
if [ -z "$BASEROW_PUBLIC_URL" ]; then
  if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    export BASEROW_PUBLIC_URL="https://$RAILWAY_PUBLIC_DOMAIN"
  else
    echo "RAILWAY_PUBLIC_DOMAIN not found, defaulting BASEROW_PUBLIC_URL to http://localhost"
    export BASEROW_PUBLIC_URL="http://localhost"
  fi
fi

# Allow all hosts to prevent 400 Bad Request errors from Django behind Railway's proxy
export BASEROW_EXTRA_ALLOWED_HOSTS="*"

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# PATCH CADDYFILE: Remove the 'tls { on_demand }' block.
# Railway terminates SSL at the edge and talks HTTP to this container.
sed -i '/^[[:blank:]]*tls {/,/^[[:blank:]]*}/d' /baserow/caddy/Caddyfile

# Execute original entrypoint
exec /baserow.sh start
