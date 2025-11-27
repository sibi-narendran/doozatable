#!/bin/bash

# Set Caddy address to the Railway PORT with explicit HTTP protocol
# This prevents Caddy from assuming HTTPS just because the port is 443 (unlikely here) or other logic
export BASEROW_CADDY_ADDRESSES="http://0.0.0.0:${PORT:-80}"

# Set Public URL to Railway Domain if available, else localhost
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
  export BASEROW_PUBLIC_URL="https://$RAILWAY_PUBLIC_DOMAIN"
else
  echo "RAILWAY_PUBLIC_DOMAIN not found, defaulting BASEROW_PUBLIC_URL to http://localhost"
  export BASEROW_PUBLIC_URL="http://localhost"
fi

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# PATCH CADDYFILE: Remove the 'tls { on_demand }' block.
# Railway terminates SSL at the edge and talks HTTP to this container.
# If we leave this block, Caddy expects an SSL handshake from Railway, causing "Client sent an HTTP request to an HTTPS server".
# We use sed to delete the block starting with 'tls {' and ending with the first '}'
sed -i '/^[[:blank:]]*tls {/,/^[[:blank:]]*}/d' /baserow/caddy/Caddyfile

# Execute original entrypoint
exec /baserow.sh start
