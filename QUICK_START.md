# HarbourX Docker 快速启动指南

## ✅ 当前状态

所有服务已成功 Docker 化并运行！

## 🚀 启动命令

```bash
# 进入 harbourX 目录
cd /Users/yafengzhu/Desktop/harbourX

# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f
```

## 📋 服务访问地址

| 服务 | 地址 | 状态 |
|------|------|------|
| **前端** | http://localhost | ✅ 运行中 |
| **后端 API** | http://localhost:8080 | ✅ 运行中 |
| **后端 Swagger** | http://localhost:8080/swagger-ui.html | ✅ 可用 |
| **AI 模块** | http://localhost:3000 | ✅ 运行中 |
| **AI 健康检查** | http://localhost:3000/health | ✅ 健康 |
| **PostgreSQL** | localhost:5433 | ✅ 运行中 |

## 🔧 常用命令

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

# 重启特定服务
docker compose restart [service-name]
```

## 📁 项目结构

```
/Users/yafengzhu/Desktop/
├── harbourX/                  # Docker 配置文件
│   ├── docker-compose.yml     # 生产环境配置
│   ├── docker-compose.dev.yml # 开发环境配置
│   ├── DOCKER_SETUP.md        # 完整部署文档
│   ├── README_DOCKER.md       # 快速参考
│   └── QUICK_START.md         # 本文件
├── HarbourX-Backend/          # Spring Boot 后端
│   └── Dockerfile
├── HarbourX-Frontend/         # React 前端
│   └── app/src/infrastructure/docker/
│       ├── Dockerfile
│       └── nginx.conf
└── AI-Module/                 # Node.js AI 服务
    └── Dockerfile
```

## 🎯 下一步

1. **访问前端**: 打开浏览器访问 http://localhost
2. **测试 API**: 访问 http://localhost:8080/swagger-ui.html
3. **查看日志**: 使用 `docker compose logs -f` 监控服务

## 📚 更多信息

- 详细文档: `DOCKER_SETUP.md`
- 快速参考: `README_DOCKER.md`

