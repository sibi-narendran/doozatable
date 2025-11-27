#!/bin/bash

# Set Public URL to include 'www' to match the GoDaddy CNAME + Forwarding setup
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://www.doozatable.com}"

# CRITICAL FIX: Allow all hosts (*)
export BASEROW_EXTRA_ALLOWED_HOSTS="*"
export BASEROW_ALLOW_ALL_HOSTS="true"

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# Define the port explicitly
APP_PORT="${PORT:-80}"

# Caddy configuration:
# We use :$APP_PORT to bind to all interfaces on that port.
# We remove 'http://' prefix which can confuse Caddy's site address matching logic in some versions.
export BASEROW_CADDY_ADDRESSES=":$APP_PORT"

cat > /baserow/caddy/Caddyfile <<EOF
{
    # Global options
    {\$BASEROW_CADDY_GLOBAL_CONF}
    # Disable admin endpoint
    admin off
    # Auto-HTTPS off because Railway handles it
    auto_https off
}

# Listen on the port defined by environment variable
:$APP_PORT {

    # 1. Backend API
    handle /api/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 2. WebSocket
    handle /ws/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 3. MCP
    handle /mcp/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 4. Assistant
    handle /assistant/* {
        reverse_proxy {\$PRIVATE_BACKEND_URL:localhost:8000}
    }

    # 5. Media Files (User Uploads)
    handle_path /media/* {
        @downloads {
            query dl=*
        }
        header @downloads Content-disposition "attachment; filename={query.dl}"

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

    # 7. Frontend (Everything else)
    handle {
        reverse_proxy {\$PRIVATE_WEB_FRONTEND_URL:localhost:3000}
    }
}
EOF

# Execute original entrypoint
exec /baserow.sh start
