# Multi-stage build for React app
FROM node:20-alpine AS base

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install ALL dependencies (including dev dependencies for build)
COPY ../HarbourX-Frontend/package.json ../HarbourX-Frontend/package-lock.json* ./
RUN npm ci

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY ../HarbourX-Frontend .

# Build the application
RUN npm run build

# Production image, copy all the files and run next
FROM nginx:alpine AS runner
WORKDIR /usr/share/nginx/html

# Copy the built application
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy logo file to root directory for favicon (index.html references /Harbour-X-Logo.png)
# Vite builds it to assets/ with hash, so we need to copy it to root
RUN find /usr/share/nginx/html/assets -name "Harbour-X-Logo*.png" -exec cp {} /usr/share/nginx/html/Harbour-X-Logo.png \;

# Copy custom nginx configuration
COPY dockerfiles/frontend/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx config that conflicts with our custom config
RUN rm -f /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
