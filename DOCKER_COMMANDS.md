# HarbourX Docker 命令指南

## 📍 工作目录

所有 Docker 命令都需要在 `harbourX` 目录下执行：

```bash
cd /Users/yafengzhu/Desktop/harbourX
```

## 🚀 启动服务

### 启动所有服务（后台运行）
```bash
docker compose up -d
```

### 启动所有服务（前台运行，查看日志）
```bash
docker compose up
```

### 启动并重新构建镜像
```bash
docker compose up -d --build
```

### 启动特定服务
```bash
docker compose up -d postgres    # 只启动数据库
docker compose up -d backend     # 只启动后端
docker compose up -d ai-module   # 只启动 AI 模块
docker compose up -d frontend    # 只启动前端
```

## 🛑 停止服务

### 停止所有服务（保留容器和数据）
```bash
docker compose stop
```

### 停止并删除容器（保留数据卷）
```bash
docker compose down
```

### 停止并删除容器和数据卷（⚠️ 会删除数据库数据）
```bash
docker compose down -v
```

### 停止特定服务
```bash
docker compose stop backend
docker compose stop frontend
docker compose stop ai-module
docker compose stop postgres
```

## 🔄 重启服务

### 重启所有服务
```bash
docker compose restart
```

### 重启特定服务
```bash
docker compose restart backend
docker compose restart frontend
docker compose restart ai-module
docker compose restart postgres
```

## 📊 查看状态

### 查看所有服务状态
```bash
docker compose ps
```

### 查看服务详细信息
```bash
docker compose ps -a
```

## 📝 查看日志

### 查看所有服务日志（实时）
```bash
docker compose logs -f
```

### 查看特定服务日志
```bash
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f ai-module
docker compose logs -f postgres
```

### 查看最近 100 行日志
```bash
docker compose logs --tail=100
```

## 🔧 其他常用命令

### 进入容器内部
```bash
# 进入后端容器
docker compose exec backend sh

# 进入数据库容器
docker compose exec postgres psql -U harbourx -d harbourx

# 进入前端容器
docker compose exec frontend sh

# 进入 AI 模块容器
docker compose exec ai-module sh
```

### 查看容器资源使用情况
```bash
docker stats
```

### 清理未使用的资源
```bash
# 清理未使用的镜像、容器、网络
docker system prune

# 清理所有未使用的资源（包括数据卷，⚠️ 谨慎使用）
docker system prune -a --volumes
```

### 查看网络
```bash
docker network ls
docker network inspect harbourx_harbourx-network
```

### 查看数据卷
```bash
docker volume ls
docker volume inspect harbourx_postgres_data
```

## 🎯 快速操作流程

### 完整启动流程
```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose up -d
docker compose ps
docker compose logs -f
```

### 完整停止流程
```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose down
```

### 重新部署流程
```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose down
docker compose up -d --build
docker compose logs -f
```

## 📋 服务访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| **前端** | http://localhost | 主应用界面 |
| **后端 API** | http://localhost:8080 | REST API |
| **后端 Swagger** | http://localhost:8080/swagger-ui.html | API 文档 |
| **AI 模块** | http://localhost:3000 | AI 服务 |
| **AI 健康检查** | http://localhost:3000/health | 健康检查 |
| **PostgreSQL** | localhost:5433 | 数据库（避免与本地冲突） |

## ⚠️ 注意事项

1. **首次启动**：首次启动可能需要几分钟来构建镜像和初始化数据库
2. **数据库数据**：使用 `docker compose down -v` 会删除所有数据库数据
3. **端口冲突**：确保端口 80、8080、3000、5433 未被占用
4. **环境变量**：AI 模块需要 `.env` 文件（在 `AI-Module/.env`）
5. **日志查看**：使用 `Ctrl+C` 退出日志查看模式

