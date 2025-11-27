#!/bin/bash

# Set Caddy address to the Railway PORT with explicit HTTP protocol
export BASEROW_CADDY_ADDRESSES="http://0.0.0.0:${PORT:-80}"

# Set Public URL to include 'www' to match the GoDaddy CNAME + Forwarding setup
# This is CRITICAL because the browser will be on 'www.doozatable.com', so Baserow must match that.
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://www.doozatable.com}"

# CRITICAL FIX: Allow all hosts (*)
export BASEROW_EXTRA_ALLOWED_HOSTS="*"
export BASEROW_ALLOW_ALL_HOSTS="true"

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# PATCH CADDYFILE: Remove the 'tls { on_demand }' block.
sed -i '/^[[:blank:]]*tls {/,/^[[:blank:]]*}/d' /baserow/caddy/Caddyfile

# Execute original entrypoint
exec /baserow.sh start
