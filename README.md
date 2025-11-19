# HarbourX Docker 部署

HarbourX 系统的 Docker 化部署配置和脚本。

## 📋 目录

- [快速开始](#快速开始)
- [服务说明](#服务说明)
- [访问地址](#访问地址)
- [常用命令](#常用命令)
- [完整命令参考](#完整命令参考)
- [数据库管理](#数据库管理)
- [故障排查](#故障排查)
- [安全建议](#安全建议)
- [开发环境](#开发环境)
- [更新服务](#更新服务)

## 🚀 快速开始

### 前置要求

- Docker Desktop 或 Docker Engine 20.10+
- Docker Compose 2.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间

### 一键启动

```bash
# 进入 harbourX 目录
cd /Users/yafengzhu/Desktop/harbourX

# 使用便捷脚本启动
./start.sh

# 或使用 Docker Compose
docker compose up -d
```

### 环境变量配置

#### 1. AI-Module 环境变量

确保 `../AI-Module/.env` 文件包含必要的 API keys：

```bash
GOOGLE_AI_API_KEY=your_google_ai_api_key
OPENAI_API_KEY=your_openai_api_key
PORT=3000
HOST=0.0.0.0
```

#### 2. JWT Secret（可选）

在 `docker-compose.yml` 中设置或使用 `.env` 文件：

```bash
JWT_SECRET=your-super-secret-jwt-key
```

## 📦 服务说明

| 服务       | 容器名               | 端口 | 说明                                        |
| ---------- | -------------------- | ---- | ------------------------------------------- |
| PostgreSQL | `harbourx-postgres`  | 5433 | 数据库服务（外部端口 5433，避免与本地冲突） |
| Backend    | `harbourx-backend`   | 8080 | Spring Boot API 服务                        |
| AI-Module  | `harbourx-ai-module` | 3000 | AI 分析服务                                 |
| Frontend   | `harbourx-frontend`  | 80   | React + Nginx 前端服务                      |

### 服务依赖关系

```
Frontend → Backend (API calls)
Frontend → AI-Module (AI analysis)
Backend → PostgreSQL (Database)
```

## 🌐 访问地址

### 生产环境

| 服务             | 地址                                  | 说明                      |
| ---------------- | ------------------------------------- | ------------------------- |
| **前端**         | http://localhost                      | 主应用界面                |
| **后端 API**     | http://localhost:8080                 | REST API                  |
| **后端 Swagger** | http://localhost:8080/swagger-ui.html | API 文档                  |
| **AI 模块**      | http://localhost:3000                 | AI 服务                   |
| **AI 健康检查**  | http://localhost:3000/health          | 健康检查                  |
| **PostgreSQL**   | localhost:5433                        | 数据库（容器内使用 5432） |

### 开发环境

使用 `docker-compose.dev.yml` 启动开发环境（带热重载）：

```bash
docker compose -f docker-compose.dev.yml up -d
```

开发环境访问地址：

- **前端**: http://localhost:3001
- **后端**: http://localhost:8080
- **AI 模块**: http://localhost:3000

## 🔧 常用命令

### 使用便捷脚本

```bash
# 启动所有服务
./start.sh

# 停止所有服务
./stop.sh

# 重启所有服务
./restart.sh
```

### 使用 Docker Compose

```bash
# 启动所有服务（后台运行）
docker compose up -d

# 停止所有服务
docker compose down

# 停止并删除数据卷（⚠️ 会删除数据库）
docker compose down -v

# 重新构建并启动
docker compose up -d --build

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f ai-module
docker compose logs -f postgres
```

## 📝 完整命令参考

> 💡 **提示**：所有 Docker 命令都需要在 `harbourX` 目录下执行。

### 启动服务

#### 启动所有服务（后台运行）

```bash
docker compose up -d
```

#### 启动所有服务（前台运行，查看日志）

```bash
docker compose up
```

#### 启动并重新构建镜像

```bash
docker compose up -d --build
```

#### 启动特定服务

```bash
docker compose up -d postgres    # 只启动数据库
docker compose up -d backend     # 只启动后端
docker compose up -d ai-module   # 只启动 AI 模块
docker compose up -d frontend    # 只启动前端
```

### 停止服务

#### 停止所有服务（保留容器和数据）

```bash
docker compose stop
```

#### 停止并删除容器（保留数据卷）

```bash
docker compose down
```

#### 停止并删除容器和数据卷（⚠️ 会删除数据库数据）

```bash
docker compose down -v
```

#### 停止特定服务

```bash
docker compose stop backend
docker compose stop frontend
docker compose stop ai-module
docker compose stop postgres
```

### 重启服务

#### 重启所有服务

```bash
docker compose restart
```

#### 重启特定服务

```bash
docker compose restart backend
docker compose restart frontend
docker compose restart ai-module
docker compose restart postgres
```

### 查看状态

#### 查看所有服务状态

```bash
docker compose ps
```

#### 查看服务详细信息

```bash
docker compose ps -a
```

### 查看日志

#### 查看所有服务日志（实时）

```bash
docker compose logs -f
```

#### 查看特定服务日志

```bash
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f ai-module
docker compose logs -f postgres
```

#### 查看最近 100 行日志

```bash
docker compose logs --tail=100
```

### 其他常用命令

#### 进入容器内部

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

#### 查看容器资源使用情况

```bash
docker stats
```

#### 清理未使用的资源

```bash
# 清理未使用的镜像、容器、网络
docker system prune

# 清理所有未使用的资源（包括数据卷，⚠️ 谨慎使用）
docker system prune -a --volumes
```

#### 查看网络

```bash
docker network ls
docker network inspect harbourx_harbourx-network
```

#### 查看数据卷

```bash
docker volume ls
docker volume inspect harbourx_postgres_data
```

### 快速操作流程

#### 完整启动流程

```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose up -d
docker compose ps
docker compose logs -f
```

#### 完整停止流程

```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose down
```

#### 重新部署流程

```bash
cd /Users/yafengzhu/Desktop/harbourX
docker compose down
docker compose up -d --build
docker compose logs -f
```

## 🗄️ 数据库管理

### 连接数据库

```bash
# 连接数据库（注意端口是 5433）
docker exec -it harbourx-postgres psql -U harbourx -d harbourx

# 或者从外部连接（端口 5433）
psql -h localhost -p 5433 -U harbourx -d harbourx
```

### 备份和恢复

```bash
# 备份数据库
docker exec harbourx-postgres pg_dump -U harbourx harbourx > backup.sql

# 恢复数据库
docker exec -i harbourx-postgres psql -U harbourx harbourx < backup.sql
```

### 数据持久化

数据卷：

- `postgres_data`: PostgreSQL 数据库数据
- `ai_module_data`: AI-Module 上传的文件和生成的数据

## 🔍 健康检查

所有服务都配置了健康检查：

```bash
# 检查所有服务健康状态
docker compose ps

# 手动检查
curl http://localhost:8080/actuator/health  # Backend
curl http://localhost:3000/health             # AI-Module
curl http://localhost                         # Frontend
```

## 🐛 故障排查

### 端口被占用

```bash
# 检查端口
lsof -i :80
lsof -i :8080
lsof -i :3000
lsof -i :5433

# 停止占用端口的进程
kill -9 <PID>
```

### 服务无法启动

1. 检查端口是否被占用（见上方）
2. 查看服务日志：

```bash
docker compose logs [service-name]
```

3. 检查环境变量：

```bash
docker compose config
```

### 数据库连接问题

1. 确保 PostgreSQL 服务已启动并健康：

```bash
docker compose ps postgres
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
docker compose logs ai-module
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

## 📝 开发环境

开发环境配置（`docker-compose.dev.yml`）提供：

- **热重载**：代码更改自动重新加载
- **开发工具**：Swagger UI、H2 Console 等
- **调试支持**：可以附加调试器

启动开发环境：

```bash
docker compose -f docker-compose.dev.yml up -d
```

## 🔄 更新服务

### 更新单个服务

```bash
# 重新构建并启动特定服务
docker compose up -d --build [service-name]
```

### 更新所有服务

```bash
# 停止所有服务
docker compose down

# 拉取最新代码
git pull

# 重新构建并启动
docker compose up -d --build
```

## 📁 项目结构

```
/Users/yafengzhu/Desktop/
├── harbourX/                  # Docker 配置文件
│   ├── docker-compose.yml     # 生产环境配置
│   ├── docker-compose.dev.yml # 开发环境配置
│   ├── start.sh               # 启动脚本
│   ├── stop.sh                # 停止脚本
│   ├── restart.sh             # 重启脚本
│   └── README.md              # 本文件
├── HarbourX-Backend/          # Spring Boot 后端
│   └── Dockerfile
├── HarbourX-Frontend/         # React 前端
│   └── app/src/infrastructure/docker/
│       ├── Dockerfile
│       └── nginx.conf
└── AI-Module/                 # Node.js AI 服务
    └── Dockerfile
```

## ⚠️ 注意事项

1. **首次启动**：首次启动可能需要几分钟来构建镜像和初始化数据库
2. **数据库数据**：使用 `docker compose down -v` 会删除所有数据库数据
3. **端口冲突**：确保端口 80、8080、3000、5433 未被占用
4. **环境变量**：AI 模块需要 `.env` 文件（在 `AI-Module/.env`）
5. **日志查看**：使用 `Ctrl+C` 退出日志查看模式

## 📚 更多资源

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Spring Boot Docker 指南](https://spring.io/guides/gs/spring-boot-docker/)
- [React Docker 最佳实践](https://mherman.org/blog/dockerizing-a-react-app/)

## 📄 License

本项目属于 HarbourX 系统的一部分。
