# ==========================================
# Stage 1: Build Frontend
# ==========================================
# We use a standard Node image to build the frontend assets.
# Using 'bookworm' to match Baserow's Debian base.
FROM node:22-bookworm-slim AS frontend-builder

WORKDIR /app

# 0. Install Build Dependencies
# 'node-sass' and other native modules require Python and C++ compilers
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# 1. Setup Directory Structure
# Baserow's Nuxt config expects sibling directories for premium/enterprise
RUN mkdir -p /premium/web-frontend /enterprise/web-frontend /web-frontend

# 2. Install Dependencies
# Copy package files first to leverage Docker cache
# Only web-frontend has a package.json in this repo structure
COPY web-frontend/package.json web-frontend/yarn.lock /web-frontend/

WORKDIR /web-frontend

# Install dependencies.
# --frozen-lockfile: Ensures we use exact versions from yarn.lock
# --ignore-engines: Bypasses the strict "node >= 24" requirement if we are on Node 22
# --network-timeout: Prevents flakey network failures
RUN yarn install --frozen-lockfile --ignore-engines --network-timeout 100000

# 3. Copy Source Code
# Copy the actual Vue/JS files after deps are installed
COPY web-frontend /web-frontend
COPY premium/web-frontend /premium/web-frontend
COPY enterprise/web-frontend /enterprise/web-frontend

# 4. Build
# Set production environment variables
ENV NODE_ENV=production
ENV BASEROW_OSS_ONLY=false

# Run the build command
# Engine check relaxed in package.json, but keeping flag for safety
RUN yarn build --ignore-engines

# ==========================================
# Stage 2: Final Runtime Image
# ==========================================
FROM baserow/baserow:2.0.1

# Switch to root to modify system files
USER root

# 1. Update Backend Code (Optional but recommended)
# Overwrite backend code with local version to ensure sync
COPY backend /baserow/backend

# 2. Setup Frontend Code
# Remove the original pre-built assets
RUN rm -rf /baserow/web-frontend/.nuxt \
    /baserow/web-frontend/node_modules

# Copy the new build artifacts from the builder stage
# CRITICAL: We must copy node_modules because Nuxt is an SSR app and needs them at runtime.
COPY --from=frontend-builder --chown=9999:9999 /web-frontend/node_modules /baserow/web-frontend/node_modules
COPY --from=frontend-builder --chown=9999:9999 /web-frontend/.nuxt /baserow/web-frontend/.nuxt

# 3. Setup Railway Entrypoint
COPY railway-entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# 4. Permissions Check
# Ensure the baserow user owns all necessary directories for runtime
RUN mkdir -p /baserow/data && \
    chown -R 9999:9999 /baserow/web-frontend /baserow/backend /baserow/data

# Switch back to the standard baserow user
USER 9999

# Start the application
ENTRYPOINT ["/railway-entrypoint.sh"]
