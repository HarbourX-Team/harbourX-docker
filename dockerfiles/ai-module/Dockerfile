# syntax=docker/dockerfile:1.6

# Stage 1: Install dependencies and build the TypeScript project
FROM node:20-alpine AS build
ARG AI_MODULE_DIR=AI-Module
WORKDIR /app

# Install pnpm via corepack and prepare dependencies
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable

# Copy dependency files first to leverage Docker layer caching
COPY ${AI_MODULE_DIR}/package.json ${AI_MODULE_DIR}/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy the remaining project files and build
COPY ${AI_MODULE_DIR} .
# Ensure public directory exists (it may be gitignored)
RUN mkdir -p public/cases public/extract/case
RUN pnpm build

# Stage 2: Create a lightweight runtime image
FROM node:20-alpine AS runtime
ARG AI_MODULE_DIR=AI-Module
WORKDIR /app
ENV NODE_ENV=production

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

# Install pnpm and only production dependencies
ENV PNPM_HOME=/home/nodejs/.local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable

# Change ownership of pnpm directory
RUN mkdir -p /home/nodejs/.local/share/pnpm && \
    chown -R nodejs:nodejs /home/nodejs

# Ensure /app directory is owned by nodejs before copying files
RUN chown -R nodejs:nodejs /app

# Copy package files and install as nodejs user
COPY --chown=nodejs:nodejs ${AI_MODULE_DIR}/package.json ${AI_MODULE_DIR}/pnpm-lock.yaml ./
USER nodejs
RUN pnpm install --frozen-lockfile --prod

# Switch back to root to install system packages
USER root

# Install runtime utilities needed for health checks
RUN apk add --no-cache curl wget

# Ensure /app is writable by nodejs (in case new files were created)
RUN chown -R nodejs:nodejs /app

# Copy the compiled application from the builder
COPY --from=build --chown=nodejs:nodejs /app/dist ./dist

# Copy public directory from build stage (we ensured it exists in build stage)
# If it doesn't exist for some reason, create empty structure
RUN --mount=from=build,source=/app,target=/tmp/build \
    if [ -d /tmp/build/public ] && [ "$(ls -A /tmp/build/public 2>/dev/null)" ]; then \
        cp -r /tmp/build/public ./public; \
    else \
        mkdir -p public/cases public/extract/case; \
    fi && \
    chown -R nodejs:nodejs ./public

# Verify dist/index.js exists
RUN test -f /app/dist/index.js || (echo "ERROR: dist/index.js not found!" && echo "Contents of /app/dist:" && ls -la /app/dist/ 2>/dev/null || echo "dist directory does not exist" && exit 1)

# Ensure the service listens on all interfaces inside the container
ENV HOST=0.0.0.0
ENV PORT=3000

# Switch to non-root user
USER nodejs

EXPOSE 3000
CMD ["node", "dist/index.js"]
