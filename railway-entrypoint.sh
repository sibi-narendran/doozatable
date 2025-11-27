#!/bin/bash

# Set Caddy address to the Railway PORT
export BASEROW_CADDY_ADDRESSES=":${PORT:-80}"

# Set Public URL to Railway Domain if available, else localhost
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
  export BASEROW_PUBLIC_URL="https://$RAILWAY_PUBLIC_DOMAIN"
else
  echo "RAILWAY_PUBLIC_DOMAIN not found, defaulting BASEROW_PUBLIC_URL to http://localhost"
  export BASEROW_PUBLIC_URL="http://localhost"
fi

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# Execute original entrypoint
exec /baserow.sh start

