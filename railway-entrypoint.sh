#!/bin/bash

# Set Caddy address to the Railway PORT with explicit HTTP protocol
# Binding to 0.0.0.0 is crucial for Railway to route traffic to it.
export BASEROW_CADDY_ADDRESSES="http://0.0.0.0:${PORT:-80}"

# Set Public URL to include 'www' to match the GoDaddy CNAME + Forwarding setup
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://www.doozatable.com}"

# CRITICAL FIX: Allow all hosts (*)
export BASEROW_EXTRA_ALLOWED_HOSTS="*"
export BASEROW_ALLOW_ALL_HOSTS="true"

# Disable volume check as Railway uses ephemeral filesystem (unless volumes are attached, but check is annoying)
export DISABLE_VOLUME_CHECK=yes

# ==================================================================================
# CRITICAL CADDY FIX:
# The default Caddyfile has a logic "@is_baserow_tool" that checks if the host header
# matches BASEROW_PUBLIC_URL.
# Since Railway's internal proxy might send the request with an IP or different host header
# initially, or if there's a mismatch (http vs https), Caddy might skip the "handle @is_baserow_tool" block
# and fall through to something else or return empty.
#
# We will PATCH the Caddyfile to REMOVE the host check condition entirely.
# We want Caddy to serve Baserow for ANY request that hits this container.
# ==================================================================================

# 1. Remove the TLS block (lines 10-12 in original)
# 2. Remove the matcher definition "@is_baserow_tool" (lines 14-16)
# 3. Remove the "handle @is_baserow_tool {" wrapper (line 18)
# 4. Remove the closing brace "}" for that handle block (line 59/60)

# We'll use a robust sed replacement to strip these lines to simplify the logic.
# This makes the Caddyfile simply say: "For any request on this port, route to backend/frontend".

sed -i '/tls {/,/}/d' /baserow/caddy/Caddyfile
sed -i '/@is_baserow_tool {/,/}/d' /baserow/caddy/Caddyfile
sed -i '/handle @is_baserow_tool {/d' /baserow/caddy/Caddyfile
# Remove the specific closing brace. This is tricky with sed blindly.
# Instead, let's just REWRITE the Caddyfile to a known good state for Railway.
# This is safer than complex sed regexes on a file we might not fully control future versions of.

cat > /baserow/caddy/Caddyfile <<EOF
{
    # Global options
    {\$BASEROW_CADDY_GLOBAL_CONF}
    # Disable admin endpoint to prevent port conflicts or security issues if exposed
    admin off
}

# Listen on the port defined by environment variable (Railway \$PORT)
{\$BASEROW_CADDY_ADDRESSES} {

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
            Access-Control-Allow-Origin {\$BASEROW_PUBLIC_URL:http://localhost}
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
