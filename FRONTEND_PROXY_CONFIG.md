# Frontend Proxy Configuration

本文档说明前端在不同环境下的代理配置，确保本地开发和生产环境使用相同的配置。

## 配置原则

**所有环境都使用 Docker 服务名进行服务发现：**
- Backend: `http://backend:8080`
- AI-Module: `http://ai-module:3000`

## 环境配置

### 开发环境 (`docker-compose.dev.yml`)

使用 Vite dev server 的 proxy 功能：

```yaml
environment:
  - VITE_BACKEND_URL=http://backend:8080
  - VITE_AI_MODULE_URL=http://ai-module:3000
```

Vite 配置 (`vite.config.ts`)：
```typescript
proxy: {
  '/api/ai': {
    target: process.env.VITE_AI_MODULE_URL || 'http://ai-module:3000',
  },
  '/api': {
    target: process.env.VITE_BACKEND_URL || 'http://backend:8080',
  },
}
```

### 生产环境 (`docker-compose.yml`)

使用 Nginx 的 proxy_pass 功能：

```yaml
environment:
  - VITE_BACKEND_URL=${VITE_BACKEND_URL:-http://backend:8080}
  - VITE_AI_MODULE_URL=${VITE_AI_MODULE_URL:-http://ai-module:3000}
```

Nginx 配置 (`nginx.conf`)：
```nginx
location /api/ai {
    set $ai_module "ai-module";
    proxy_pass http://$ai_module:3000;
}

location /api/ {
    set $backend "backend";
    proxy_pass http://$backend:8080;
}
```

## 路由规则

1. **`/api/ai/*`** → AI-Module (`ai-module:3000`)
   - 必须放在 `/api/` 之前，优先匹配
   
2. **`/api/*`** → Backend (`backend:8080`)
   - 匹配所有其他 `/api/` 请求

## 一致性保证

- ✅ 两个环境都使用相同的 Docker 服务名
- ✅ 两个环境都在同一个 Docker 网络中
- ✅ 默认值都是 `http://backend:8080` 和 `http://ai-module:3000`
- ✅ 可以通过环境变量覆盖（如果需要）

## 本地直接运行（不在 Docker 中）

如果需要本地直接运行 `npm run dev`（不在 Docker 中），需要设置环境变量：

```bash
# 创建 .env.local 文件
VITE_BACKEND_URL=http://localhost:8080
VITE_AI_MODULE_URL=http://localhost:3000
```

或者运行时设置：
```bash
VITE_BACKEND_URL=http://localhost:8080 npm run dev
```

## 验证配置

### 开发环境
```bash
./harbourx.sh docker start:dev
# 访问 http://localhost:3001
```

### 生产环境
```bash
./harbourx.sh docker start
# 访问 http://localhost
```

### 部署到 EC2
```bash
./harbourx.sh deploy deploy
# 访问 http://13.54.207.94
```

所有环境都应该能够正常访问 `/api/auth/login` 等后端 API。

