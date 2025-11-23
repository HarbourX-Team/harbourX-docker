# Multi-stage build for React app
FROM node:20-alpine AS base

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install ALL dependencies (including dev dependencies for build)
COPY package.json package-lock.json* ./
RUN npm ci

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Copy nginx.conf to builder stage so it's available for runner stage
COPY app/src/infrastructure/docker/nginx.conf /tmp/nginx.conf

# Build the application
RUN npm run build

# Production image, copy all the files and run next
FROM nginx:alpine AS runner
ARG FRONTEND_DIR=HarbourX-Frontend
ARG HARBOURX_DIR=harbourX
WORKDIR /usr/share/nginx/html

# Note: Nginx main process runs as root (required for binding port 80)
# Worker processes run as nginx user (configured in nginx.conf)
# This is the standard and secure approach for Nginx in containers

# Copy the built application
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy logo file to root directory for favicon (index.html references /Harbour-X-Logo.png)
# Vite builds it to assets/ with hash, so we need to copy it to root
# Use || true to avoid failure if file doesn't exist
RUN find /usr/share/nginx/html/assets -name "Harbour-X-Logo*.png" -exec cp {} /usr/share/nginx/html/Harbour-X-Logo.png \; || true

# Copy custom nginx configuration from builder stage
COPY --from=builder /tmp/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx config that conflicts with our custom config
RUN rm -f /etc/nginx/conf.d/default.conf

# Set proper permissions for nginx user (worker processes)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx

# Expose port 80
EXPOSE 80

# Start nginx (main process as root, workers as nginx user)
CMD ["nginx", "-g", "daemon off;"]
