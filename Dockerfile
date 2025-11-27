FROM baserow/baserow:2.0.1

# Override the Caddy addresses to listen on the Railway-provided PORT
# We use a shell command to dynamically set the environment variable based on $PORT
# But since we can't easily change the entrypoint logic without a wrapper, 
# we'll rely on Caddy reading the environment variable if we can set it.

# Baserow Caddyfile uses {$BASEROW_CADDY_ADDRESSES}
# We need BASEROW_CADDY_ADDRESSES to be set to :$PORT at runtime.
# We can do this by overriding the CMD or ENTRYPOINT.

COPY railway-entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

ENTRYPOINT ["/railway-entrypoint.sh"]

