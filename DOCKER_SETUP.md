# HarbourX Docker 化部署指南

本文档说明如何使用 Docker 和 Docker Compose 部署整个 HarbourX 系统（Backend、Frontend、AI-Module）。

## 📋 前置要求

- Docker Desktop 或 Docker Engine 20.10+
- Docker Compose 2.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间

## 🚀 快速开始

### 1. 准备环境变量

复制环境变量模板：

```bash
cp .env.example .env
```

编辑 `.env` 文件，设置必要的环境变量（特别是 JWT_SECRET 和 AI API keys）。

### 2. 配置 AI-Module 环境变量

确保 `AI-Module/.env` 文件包含必要的 API keys：

```bash
# 在 AI-Module 目录下
cp .env.example .env  # 如果存在
# 编辑 .env 文件，添加：
GOOGLE_AI_API_KEY=your_google_ai_api_key
OPENAI_API_KEY=your_openai_api_key
```

### 3. 启动所有服务（生产环境）

```bash
docker-compose up -d
```

### 4. 启动开发环境（带热重载）

```bash
docker-compose -f docker-compose.dev.yml up -d
```

## 📦 服务说明

### 服务列表

| 服务 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| PostgreSQL | `harbourx-postgres` | 5432 | 数据库服务 |
| Backend | `harbourx-backend` | 8080 | Spring Boot API 服务 |
| AI-Module | `harbourx-ai-module` | 3000 | AI 分析服务 |
| Frontend | `harbourx-frontend` | 80 | React + Nginx 前端服务 |

### 服务依赖关系

```
Frontend → Backend (API calls)
Frontend → AI-Module (AI analysis)
Backend → PostgreSQL (Database)
```

## 🔧 常用命令

### 查看服务状态

```bash
docker-compose ps
```

### 查看日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f backend
docker-compose logs -f frontend
docker-compose logs -f ai-module
docker-compose logs -f postgres
```

### 停止服务

```bash
docker-compose down
```

### 停止并删除数据卷（⚠️ 会删除数据库数据）

```bash
docker-compose down -v
```

### 重新构建并启动

```bash
docker-compose up -d --build
```

### 进入容器

```bash
# Backend
docker exec -it harbourx-backend sh

# Frontend
docker exec -it harbourx-frontend sh

# AI-Module
docker exec -it harbourx-ai-module sh

# PostgreSQL
docker exec -it harbourx-postgres psql -U harbourx -d harbourx
```

## 🌐 访问地址

### 生产环境

- **Frontend**: http://localhost
- **Backend API**: http://localhost:8080
- **Backend Swagger**: http://localhost:8080/swagger-ui.html
- **AI-Module**: http://localhost:3000
- **AI-Module Health**: http://localhost:3000/health
- **PostgreSQL**: localhost:5432

### 开发环境

- **Frontend**: http://localhost:3001
- **Backend API**: http://localhost:8080
- **AI-Module**: http://localhost:3000

## 🔍 健康检查

所有服务都配置了健康检查：

```bash
# 检查所有服务健康状态
docker-compose ps

# 手动检查
curl http://localhost:8080/actuator/health  # Backend
curl http://localhost:3000/health           # AI-Module
curl http://localhost                       # Frontend
```

## 🗄️ 数据持久化

### 数据卷

- `postgres_data`: PostgreSQL 数据库数据
- `ai_module_data`: AI-Module 上传的文件和生成的数据

### 备份数据库

```bash
# 备份
docker exec harbourx-postgres pg_dump -U harbourx harbourx > backup.sql

# 恢复
docker exec -i harbourx-postgres psql -U harbourx harbourx < backup.sql
```

## 🐛 故障排查

### 服务无法启动

1. 检查端口是否被占用：
```bash
lsof -i :80
lsof -i :8080
lsof -i :3000
lsof -i :5432
```

2. 查看服务日志：
```bash
docker-compose logs [service-name]
```

3. 检查环境变量：
```bash
docker-compose config
```

### 数据库连接问题

1. 确保 PostgreSQL 服务已启动并健康：
```bash
docker-compose ps postgres
```

2. 检查数据库连接：
```bash
docker exec -it harbourx-postgres psql -U harbourx -d harbourx -c "SELECT 1;"
```

### Frontend 无法连接 Backend

1. 检查 `vite.config.ts` 中的代理配置
2. 确保 Backend 服务正常运行
3. 检查 CORS 配置

### AI-Module 无法工作

1. 检查 `.env` 文件中的 API keys
2. 查看 AI-Module 日志：
```bash
docker-compose logs ai-module
```

## 🔐 安全建议

### 生产环境

1. **更改默认密码**：修改 `docker-compose.yml` 中的数据库密码
2. **使用强 JWT Secret**：在 `.env` 文件中设置强随机字符串
3. **限制端口暴露**：只暴露必要的端口
4. **使用 HTTPS**：配置反向代理（如 Nginx）和 SSL 证书
5. **定期备份**：设置数据库自动备份

### 环境变量安全

- 不要将 `.env` 文件提交到版本控制
- 使用 Docker secrets 或外部密钥管理服务（如 AWS Secrets Manager）

## 📝 开发环境说明

开发环境配置（`docker-compose.dev.yml`）提供：

- **热重载**：代码更改自动重新加载
- **开发工具**：Swagger UI、H2 Console 等
- **调试支持**：可以附加调试器

启动开发环境：

```bash
docker-compose -f docker-compose.dev.yml up -d
```

## 🔄 更新服务

### 更新单个服务

```bash
# 重新构建并启动特定服务
docker-compose up -d --build [service-name]
```

### 更新所有服务

```bash
# 停止所有服务
docker-compose down

# 拉取最新代码
git pull

# 重新构建并启动
docker-compose up -d --build
```

## 📚 更多资源

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Spring Boot Docker 指南](https://spring.io/guides/gs/spring-boot-docker/)
- [React Docker 最佳实践](https://mherman.org/blog/dockerizing-a-react-app/)

