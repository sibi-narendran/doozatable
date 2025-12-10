FROM baserow/baserow:1.29.1

# Switch to root to perform installations and file copies
USER root

# Install dependencies required for rebuilding frontend
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy your local source code into the image
# We overwrite the existing files in the image with your modified versions
COPY web-frontend /baserow/web-frontend
COPY backend /baserow/backend
COPY premium /baserow/premium
COPY enterprise /baserow/enterprise

# Rebuild the frontend
# We set the workdir to the frontend directory
WORKDIR /baserow/web-frontend

# Install dependencies (in case you changed package.json, otherwise this might be fast)
# We use --production=false because we need devDependencies to build
RUN yarn install --production=false

# Run the build command
# This generates the new .nuxt directory with your new logos and text
RUN yarn build

# Restore permissions (crucial because we are running as root)
RUN chown -R 9999:9999 /baserow

# Switch back to the baserow user
USER 9999

# Railway Entrypoint Setup
COPY railway-entrypoint.sh /railway-entrypoint.sh
USER root
RUN chmod +x /railway-entrypoint.sh
USER 9999

ENTRYPOINT ["/railway-entrypoint.sh"]
