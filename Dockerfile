# Stage 1: Build Frontend
FROM node:22-bookworm-slim AS frontend-builder

WORKDIR /app

# Create directory structure to match relative imports in nuxt.config
RUN mkdir -p /premium/web-frontend /enterprise/web-frontend /web-frontend

# Copy package.json and yarn.lock for caching
COPY web-frontend/package.json web-frontend/yarn.lock /web-frontend/

WORKDIR /web-frontend

# Install dependencies
# Using --ignore-engines to bypass potential Node version mismatches
RUN yarn install --frozen-lockfile --ignore-engines

# Copy the rest of the frontend source code
COPY web-frontend /web-frontend
COPY premium/web-frontend /premium/web-frontend
COPY enterprise/web-frontend /enterprise/web-frontend

# Build Environment Variables
ENV NODE_ENV=production
ENV BASEROW_OSS_ONLY=false

# Run the build
RUN yarn build

# Stage 2: Final Runtime Image
FROM baserow/baserow:2.0.1

# Switch to root to modify files
USER root

# 1. Update Backend Code
# Copy local backend files to overwrite the image's backend
COPY backend /baserow/backend

# 2. Update Frontend Code
# Remove the pre-built frontend assets
RUN rm -rf /baserow/web-frontend/.nuxt /baserow/web-frontend/static

# Copy the newly built assets from the builder stage
# Ensure ownership matches the baserow user (UID 9999)
COPY --from=frontend-builder --chown=9999:9999 /web-frontend/.nuxt /baserow/web-frontend/.nuxt
COPY --from=frontend-builder --chown=9999:9999 /web-frontend/static /baserow/web-frontend/static

# 3. Setup Railway Entrypoint
COPY railway-entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Switch back to the baserow user
USER 9999

ENTRYPOINT ["/railway-entrypoint.sh"]
