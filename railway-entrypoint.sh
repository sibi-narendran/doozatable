#!/bin/bash

# ==================================================================================
# BASEROW RAILWAY ENTRYPOINT (PRODUCTION)
# ==================================================================================

# 0. DISABLE EMBEDDED SERVICES (CRITICAL!)
# -----------------------------------------
# Railway requires external PostgreSQL and Redis.
# We MUST tell Baserow to disable the embedded services, otherwise the supervisor
# `processes` event listener will fail trying to manage them.
#
# These variables prevent Baserow from attempting to start/manage embedded databases.

if [ -n "$DATABASE_URL" ] || [ -n "$DATABASE_HOST" ]; then
    echo "External PostgreSQL detected. Disabling embedded postgres."
    export DISABLE_EMBEDDED_PSQL=yes
else
    echo "ERROR: No DATABASE_URL or DATABASE_HOST provided!"
    echo "Railway deployment requires external PostgreSQL."
    echo "Please add a PostgreSQL database to your Railway project."
    exit 1
fi

if [ -n "$REDIS_URL" ] || [ -n "$REDIS_HOST" ]; then
    echo "External Redis detected. Disabling embedded redis."
    export DISABLE_EMBEDDED_REDIS=yes
else
    echo "ERROR: No REDIS_URL or REDIS_HOST provided!"
    echo "Railway deployment requires external Redis."
    echo "Please add a Redis database to your Railway project."
    exit 1
fi

# 1. PUBLIC URL CONFIGURATION
# ---------------------------
# If RAILWAY_PUBLIC_DOMAIN is provided by Railway, use it automatically.
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    export BASEROW_PUBLIC_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi

# Otherwise default to tables.dooza.co if no specific override is provided.
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://tables.dooza.co}"

# 2. SECURITY & HOSTING
# ---------------------
# Auto-generate secrets if missing (prevents crash on first deploy)
if [ -z "$SECRET_KEY" ]; then
    echo "WARNING: SECRET_KEY not set. Generating a random one."
    export SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
fi

if [ -z "$BASEROW_JWT_SIGNING_KEY" ]; then
    echo "WARNING: BASEROW_JWT_SIGNING_KEY not set. Generating a random one."
    export BASEROW_JWT_SIGNING_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
fi

# Enable SSL trust for Railway Load Balancer
export BASEROW_ENABLE_SECURE_PROXY_SSL_HEADER="true"

# Railway puts the app behind a load balancer (Envoy).
# We must trust all incoming Host headers because the LB terminates SSL and forwards traffic.
export BASEROW_EXTRA_ALLOWED_HOSTS="*"
export BASEROW_ALLOW_ALL_HOSTS="true"

# 3. STORAGE CONFIGURATION
# ------------------------
# Railway storage is ephemeral unless a volume is mounted.
# We disable the check to allow the app to start even if the volume mount is tricky (though we added one).
export DISABLE_VOLUME_CHECK=yes

# 4. CADDY CONFIGURATION (THE CORE FIX)
# -------------------------------------
# Railway assigns a random port to the container and provides it in the $PORT env var.
# We MUST listen on this port. We cannot hardcode 80.
# We bind to 0.0.0.0 to accept external connections.

APP_PORT="${PORT:-80}"
export BASEROW_CADDY_ADDRESSES=":$APP_PORT"

# We completely rewrite the Caddyfile to ensure it's compatible with Railway's architecture.
# - Remove auto_https (Railway handles SSL)
# - Remove host matching (Trust Railway routing)
# - Proxy explicitly to internal services

cat > /baserow/caddy/Caddyfile <<EOF
{
    # Global options from Baserow
    {\$BASEROW_CADDY_GLOBAL_CONF}
    
    # Turn off admin API to prevent port conflicts
    admin off
    
    # Turn off auto_https because Railway terminates TLS at the edge
    auto_https off
}

# Listen on the Railway-assigned port
:$APP_PORT {

    # LOGGING: Enable access logs for debugging
    log {
        output stderr
        format console
    }

    # PROXY HEADERS: Ensure downstream services know about the original IP/Protocol
    # Railway sends X-Forwarded-Proto: https, so Caddy should pass that along.

    # 1. Backend API (Django)
    handle /api/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000} {
            header_up Host {http.request.host}
            header_up X-Real-IP {http.request.remote.host}
            header_up X-Forwarded-Proto {http.request.header.X-Forwarded-Proto}
        }
    }

    # 2. WebSocket (Daphne/Channels)
    handle /ws/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000} {
            header_up Host {http.request.host}
            header_up X-Real-IP {http.request.remote.host}
            header_up X-Forwarded-Proto {http.request.header.X-Forwarded-Proto}
        }
    }

    # 3. MCP (Model Context Protocol)
    handle /mcp/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 4. AI Assistant
    handle /assistant/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 5. Media Files (User Uploads)
    # We serve these directly from disk for performance.
    handle_path /media/* {
        @downloads {
            query dl=*
        }
        header @downloads Content-disposition "attachment; filename={query.dl}"

        # CORS Headers for Media
        header {
            Access-Control-Allow-Origin *
            Access-Control-Allow-Methods "GET, HEAD, OPTIONS"
            Access-Control-Allow-Headers "*"
            Access-Control-Expose-Headers "Content-Length, Content-Type"
        }
        file_server {
            root {\$MEDIA_ROOT:/baserow/media/}
        }
    }

    # 6. Static Files (CSS/JS)
    handle_path /static/* {
        file_server {
            root {\$STATIC_ROOT:/baserow/static/}
        }
    }

    # 7. Frontend (Nuxt.js)
    # This is the default handler for all other routes.
    handle {
        reverse_proxy {\$PRIVATE_WEB_FRONTEND_URL:localhost:3000} {
            header_up Host {http.request.host}
            header_up X-Real-IP {http.request.remote.host}
            header_up X-Forwarded-Proto {http.request.header.X-Forwarded-Proto}
        }
    }
}
EOF

# Determine if using external services
if [ -n "$REDIS_URL" ] || [ -n "$REDIS_HOST" ]; then
    REDIS_STATUS="external"
else
    REDIS_STATUS="embedded"
fi

if [ -n "$DATABASE_URL" ] || [ -n "$DATABASE_HOST" ]; then
    DB_STATUS="external"
else
    DB_STATUS="embedded"
fi

echo "================================================================"
echo " RAILWAY ENTRYPOINT STARTING"
echo "================================================================"
echo " PORT: $APP_PORT"
echo " PUBLIC_URL: $BASEROW_PUBLIC_URL"
echo " REDIS: $REDIS_STATUS"
echo " DATABASE: $DB_STATUS"
echo "================================================================"
echo " Note: Baserow startup takes 2-4 minutes. Be patient."
echo "================================================================"

# 5. FIX PERMISSIONS
# -------------------
# Railway mounts volumes as root, so we fix ownership before starting
echo "Fixing permissions for /baserow/data, /baserow/media, and /baserow/caddy..."

# Create directories if they don't exist
mkdir -p /baserow/data /baserow/media /baserow/caddy

# Attempt ownership fix (will partially succeed on Railway - new files will work)
# We use --no-dereference to not follow symlinks, and ignore errors
chown -R --no-dereference 9999:9999 /baserow/data /baserow/media /baserow/caddy 2>/dev/null || true

# Ensure Media/Caddy are writable
chmod -R 777 /baserow/media /baserow/caddy 2>/dev/null || true

# 6. FIX EVENT LISTENER BUG
# --------------------------
# The stop-supervisor.sh script has `set -e` and can fail if supervisord.pid
# doesn't exist yet when an event arrives. This causes the entire container to die.
# We patch it to handle missing PID file gracefully.
if [ -f /baserow/supervisor/stop-supervisor.sh ]; then
    cat > /baserow/supervisor/stop-supervisor.sh << 'STOPSCRIPT'
#!/usr/bin/env bash
# Patched version: Removed set -e to prevent early exit on missing PID file

# This file implements supervisord's eventlistener protocol
# See: http://supervisord.org/events.html#event-listeners-and-event-notifications

printf "READY\n";

while read -r; do
  echo -e "\e[31mBaserow was stopped or one of its services crashed, see the logs above for more details. \e[0m" >&2
  # Use || true to prevent exit if PID file doesn't exist yet
  if [ -f supervisord.pid ]; then
    kill -SIGTERM "$(cat supervisord.pid)" || true
  fi
done < /dev/stdin
STOPSCRIPT
    chmod +x /baserow/supervisor/stop-supervisor.sh
fi

# 7. START BASEROW
# ----------------
echo "Starting Baserow..."
exec /baserow.sh start
