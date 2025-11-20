# syntax=docker/dockerfile:1.6

# Stage 1: Install dependencies and build the TypeScript project
FROM node:20-alpine AS build
WORKDIR /app

# Install pnpm via corepack and prepare dependencies
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable

# Copy dependency files first to leverage Docker layer caching
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy the remaining project files and build
COPY . .
RUN pnpm build

# Stage 2: Create a lightweight runtime image
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Install pnpm and only production dependencies
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

# Install runtime utilities needed for health checks
RUN apk add --no-cache curl

# Copy the compiled application and static assets from the builder
COPY --from=build /app/dist ./dist
COPY --from=build /app/public ./public

# Verify dist/index.js exists
RUN test -f /app/dist/index.js || (echo "ERROR: dist/index.js not found!" && echo "Contents of /app/dist:" && ls -la /app/dist/ 2>/dev/null || echo "dist directory does not exist" && exit 1)

# Ensure the service listens on all interfaces inside the container
ENV HOST=0.0.0.0
ENV PORT=3000

EXPOSE 3000
CMD ["node", "dist/index.js"]
