#!/bin/bash

# ==================================================================================
# BASEROW RAILWAY ENTRYPOINT (PRODUCTION)
# ==================================================================================

# 1. PUBLIC URL CONFIGURATION
# ---------------------------
# We are switching to the 'app' subdomain logic.
# If RAILWAY_PUBLIC_DOMAIN is set (by Railway), use it.
# Otherwise default to app.doozatable.com if no specific override is provided.
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://app.doozatable.com}"

# 2. SECURITY & HOSTING
# ---------------------
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

echo "----------------------------------------------------------------"
echo " RAILWAY ENTRYPOINT STARTING"
echo " PORT: $APP_PORT"
echo " PUBLIC_URL: $BASEROW_PUBLIC_URL"
echo "----------------------------------------------------------------"

# Execute the original Baserow entrypoint
# 1. Fix permissions for the mounted volume
# Railway mounts volumes as root, so we must fix ownership before dropping privileges
echo "Fixing permissions for /baserow/data..."
chown -R 9999:9999 /baserow/data

# 2. Start Baserow as the correct user
# We use 'su-exec' to switch from root to baserow_docker_user (9999)
# We use 'exec' to replace the shell with the process (for signal handling)
exec su-exec 9999:9999 /baserow.sh start
