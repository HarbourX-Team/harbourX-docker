# HarbourX Docker 部署快速指南

## 🚀 一键启动

```bash
# 1. 进入 harbourX 目录
cd /Users/yafengzhu/Desktop/harbourX

# 2. 启动所有服务
docker compose up -d

# 3. 查看服务状态
docker compose ps

# 4. 查看日志
docker compose logs -f
```

## 📋 服务访问地址

- **前端**: http://localhost
- **后端 API**: http://localhost:8080
- **后端 Swagger**: http://localhost:8080/swagger-ui.html
- **AI 模块**: http://localhost:3000
- **AI 模块健康检查**: http://localhost:3000/health
- **PostgreSQL**: localhost:5433 (容器内使用 5432)

## 🔧 环境变量配置

### 必需配置

1. **AI-Module 环境变量** (`../AI-Module/.env`):
```bash
GOOGLE_AI_API_KEY=your_google_ai_api_key
OPENAI_API_KEY=your_openai_api_key
PORT=3000
HOST=0.0.0.0
```

2. **JWT Secret** (可选，在 `docker-compose.yml` 中设置或使用 `.env` 文件):
```bash
JWT_SECRET=your-super-secret-jwt-key
```

## 🛠️ 常用命令

```bash
# 停止所有服务
docker compose down

# 停止并删除数据卷（⚠️ 会删除数据库）
docker compose down -v

# 重新构建并启动
docker compose up -d --build

# 查看特定服务日志
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f ai-module
docker compose logs -f postgres

# 进入容器
docker exec -it harbourx-backend sh
docker exec -it harbourx-frontend sh
docker exec -it harbourx-ai-module sh
```

## 🗄️ 数据库管理

```bash
# 连接数据库（注意端口是 5433）
docker exec -it harbourx-postgres psql -U harbourx -d harbourx

# 或者从外部连接（端口 5433）
psql -h localhost -p 5433 -U harbourx -d harbourx

# 备份数据库
docker exec harbourx-postgres pg_dump -U harbourx harbourx > backup.sql

# 恢复数据库
docker exec -i harbourx-postgres psql -U harbourx harbourx < backup.sql
```

## 📝 开发环境

使用开发配置（带热重载）：

```bash
docker compose -f docker-compose.dev.yml up -d
```

开发环境访问地址：
- **前端**: http://localhost:3001
- **后端**: http://localhost:8080
- **AI 模块**: http://localhost:3000

## 🐛 故障排查

### 端口被占用
```bash
# 检查端口
lsof -i :80
lsof -i :8080
lsof -i :3000
lsof -i :5433  # Docker PostgreSQL 使用 5433

# 停止占用端口的进程
kill -9 <PID>
```

### 服务无法启动
```bash
# 查看详细日志
docker compose logs [service-name]

# 检查服务健康状态
docker compose ps
```

### 数据库连接问题
```bash
# 检查 PostgreSQL 是否运行
docker compose ps postgres

# 测试数据库连接
docker exec -it harbourx-postgres psql -U harbourx -d harbourx -c "SELECT 1;"
```

### AI-Module 构建问题
如果 AI-Module 启动失败，检查构建：
```bash
# 查看构建日志
docker compose logs ai-module

# 重新构建
docker compose build ai-module
docker compose up -d ai-module
```

## 📚 详细文档

查看 `DOCKER_SETUP.md` 获取完整的部署文档。
