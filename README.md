# HarbourX Docker 部署完整指南

HarbourX 系统的 Docker 化部署配置、CI/CD 流程和 AWS EC2 部署指南。

---

## ⚠️ 部署前必需：登录信息配置

**在开始部署之前，必须配置以下登录信息：**

### 🔐 必需的登录信息

#### 1. **GitHub 认证**（必需）

部署脚本需要 GitHub 认证来拉取代码。请使用以下**三种方法之一**：

**方法 1: 使用 GitHub CLI（推荐）**

```bash
# 安装 GitHub CLI（如果未安装）
# macOS: brew install gh
# Linux: 参考 https://cli.github.com/

# 登录 GitHub
gh auth login

# 验证登录状态
gh auth status
```

**方法 2: 设置环境变量**

```bash
# 生成 Personal Access Token
# 1. 访问 https://github.com/settings/tokens
# 2. 点击 "Generate new token (classic)"
# 3. 选择权限: repo (完整仓库访问权限)
# 4. 复制生成的 token

# 设置环境变量
export GITHUB_TOKEN='your_github_token_here'

# 验证（可选）
echo $GITHUB_TOKEN
```

**方法 3: 在 ~/.zshrc 或 ~/.bashrc 中永久设置**

```bash
# 添加到 ~/.zshrc 或 ~/.bashrc
export GITHUB_TOKEN='your_github_token_here'

# 重新加载配置
source ~/.zshrc  # 或 source ~/.bashrc
```

#### 2. **SSH 密钥配置**（必需）

部署到 EC2 需要 SSH 密钥：

```bash
# 设置 SSH 密钥路径
export SSH_KEY=~/.ssh/harbourX-demo-key-pair.pem

# 或使用脚本默认路径
# 默认: ~/.ssh/harbourX-demo-key-pair.pem
```

#### 3. **EC2 连接信息**（必需）

```bash
# 设置 EC2 主机地址
export EC2_HOST=13.54.207.94

# 设置 EC2 用户（可选，默认: ec2-user）
export EC2_USER=ec2-user
```

### ✅ 验证配置

运行以下命令验证所有必需配置：

```bash
# 检查 GitHub 登录
gh auth status || echo "⚠️  GitHub CLI 未登录"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:+已设置}" || echo "⚠️  GITHUB_TOKEN 未设置"

# 检查 SSH 密钥
[ -f "${SSH_KEY:-~/.ssh/harbourX-demo-key-pair.pem}" ] && echo "✅ SSH 密钥存在" || echo "⚠️  SSH 密钥不存在"

# 检查 EC2 配置
echo "EC2_HOST: ${EC2_HOST:-未设置}"
echo "EC2_USER: ${EC2_USER:-ec2-user (默认)}"
```

### 🚨 常见问题

**Q: 为什么需要 GitHub 认证？**
A: 部署脚本需要从 GitHub 拉取最新代码（Backend 和 Frontend），私有仓库或频繁拉取需要认证。

**Q: 如何获取 GitHub Personal Access Token？**
A:

1. 访问 https://github.com/settings/tokens
2. 点击 "Generate new token (classic)"
3. 选择 `repo` 权限
4. 复制并保存 token（只显示一次）

**Q: 部署时提示 "GitHub 登录验证失败"？**
A:

- 检查 token 是否有效：`curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user`
- 或运行 `gh auth login` 重新登录
- 确保 token 有 `repo` 权限

---

## 📋 目录

- [🚀 快速开始](#-快速开始)
- [📦 服务说明](#-服务说明)
- [🌐 访问地址](#-访问地址)
- [🔧 常用命令](#-常用命令)
- [📝 完整命令参考](#-完整命令参考)
- [🗄️ 数据库管理](#️-数据库管理)
- [🔍 健康检查](#-健康检查)
- [🐛 故障排查](#-故障排查)
- [🔐 安全建议](#-安全建议)
- [📝 开发环境](#-开发环境)
- [🔄 更新服务](#-更新服务)
- [🌐 AWS EC2 部署](#-aws-ec2-部署)
- [🔄 CI/CD 工作流程](#-cicd-工作流程)
- [🔐 GitHub CI/CD 配置](#-github-cicd-配置)

---

## 🚀 快速开始

### 前置要求

- Docker Desktop 或 Docker Engine 20.10+
- Docker Compose 2.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间

### 一键启动

#### 方法 1：本地完整部署（推荐首次使用）

```bash
# 进入 harbourX 目录
cd harbourX

# 本地完整部署（自动检查环境、构建并启动）
./harbourx.sh deploy local          # 生产环境
./harbourx.sh deploy local dev      # 开发环境
```

#### 方法 2：快速启动（已部署过）

```bash
# 使用统一管理脚本启动（生产环境）
./harbourx.sh docker start

# 或启动开发环境（带热重载）
./harbourx.sh docker start:dev

# 或直接使用 Docker Compose
docker compose up -d
```

### 环境变量配置

> ⚠️ **重要**：生产环境部署前，必须配置以下环境变量以确保安全性！

#### 1. 创建 .env 文件（生产环境必需）

```bash
# 复制示例文件
cp .env.example .env

# 编辑 .env 文件，设置所有必需的配置
```

#### 2. 生产环境必需配置

**必须设置以下环境变量（生产环境）：**

```bash
# 项目路径配置（如果项目结构不同）
PROJECT_ROOT=..                    # 项目根目录（相对于 harbourX 文件夹）
BACKEND_DIR=HarbourX-Backend      # Backend 目录名
FRONTEND_DIR=HarbourX-Frontend    # Frontend 目录名
AI_MODULE_DIR=AI-Module           # AI-Module 目录名
DOCKER_DIR=harbourX              # Docker 配置目录名

# 数据库配置（生产环境必须更改默认密码！）
POSTGRES_DB=harbourx
POSTGRES_USER=harbourx
POSTGRES_PASSWORD=CHANGE_THIS_PASSWORD_IN_PRODUCTION  # ⚠️ 必须更改！
DB_PORT=5432

# JWT Secret（生产环境必须设置！）
# 生成安全的 JWT Secret（至少 256 位）：
# openssl rand -base64 32
JWT_SECRET=CHANGE_THIS_JWT_SECRET_IN_PRODUCTION  # ⚠️ 必须更改！

# Frontend Allowed Origins（根据实际情况调整）
FRONTEND_ALLOWED_ORIGINS=http://localhost:3001,http://localhost:80,http://frontend:80
```

#### 3. AI-Module 环境变量

确保 `${PROJECT_ROOT}/${AI_MODULE_DIR}/.env` 文件（默认 `../AI-Module/.env`）包含必要的 API keys：

```bash
GOOGLE_AI_API_KEY=your_google_ai_api_key
OPENAI_API_KEY=your_openai_api_key
PORT=3000
HOST=0.0.0.0
```

#### 4. 生成安全的 JWT Secret

```bash
# 方法 1：使用 OpenSSL（推荐）
openssl rand -base64 32

# 方法 2：使用 /dev/urandom
head -c 32 /dev/urandom | base64

# 将生成的字符串设置为 JWT_SECRET 环境变量
```

> 💡 **提示**：JWT Secret 应该：
>
> - 至少 256 位（32 字节）
> - 使用随机生成的字符串
> - 不要使用可预测的值
> - 在生产环境中定期轮换

---

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

---

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

---

## 🔧 常用命令

### 使用统一管理脚本（推荐）

`harbourx.sh` 是一个统一的管理脚本，整合了所有 Docker 和部署操作。

#### Docker 操作

```bash
# 启动所有服务（生产环境）
./harbourx.sh docker start

# 启动开发环境（带热重载）
./harbourx.sh docker start:dev

# 停止所有服务
./harbourx.sh docker stop

# 重启所有服务
./harbourx.sh docker restart

# 查看服务状态
./harbourx.sh docker status

# 查看日志（所有服务）
./harbourx.sh docker logs

# 查看特定服务日志
./harbourx.sh docker logs backend

# 清理所有 Docker 资源（镜像、容器、卷）
./harbourx.sh docker clean
```

#### 部署操作

```bash
# 本地完整部署（推荐首次使用）
./harbourx.sh deploy local          # 生产环境，重新构建
./harbourx.sh deploy local dev       # 开发环境，重新构建
./harbourx.sh deploy local prod false  # 生产环境，不重新构建

# 部署到 EC2 实例
./harbourx.sh deploy deploy

# SSH 连接到 EC2
./harbourx.sh deploy ssh

# 获取 EC2 实例 IP
./harbourx.sh deploy ip

# 在 EC2 上设置 Git 仓库
./harbourx.sh deploy setup-git

# 在云端创建 Broker
./harbourx.sh deploy create-broker
```

> 💡 **本地部署** (`deploy local`) 会自动：
>
> - 检查 Docker 环境
> - 验证项目结构
> - 检查环境变量文件
> - 停止现有服务
> - 构建并启动所有服务
> - 执行健康检查
> - 显示访问地址和状态

#### 配置操作

```bash
# 查看当前配置
./harbourx.sh config env

# 查看完整帮助
./harbourx.sh help
```

#### 环境变量

可以通过环境变量自定义配置：

```bash
export EC2_HOST=13.54.207.94
export EC2_USER=ec2-user
export SSH_KEY=~/.ssh/harbourX-demo-key-pair.pem
export PROJECT_ROOT=..
export BACKEND_DIR=HarbourX-Backend
export FRONTEND_DIR=HarbourX-Frontend
export AI_MODULE_DIR=AI-Module
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

---

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
cd harbourX
./harbourx.sh docker start
# 或
docker compose up -d
docker compose ps
docker compose logs -f
```

#### 完整停止流程

```bash
cd harbourX
./harbourx.sh docker stop
# 或
docker compose down
```

#### 重新部署流程

```bash
cd harbourX
./harbourx.sh docker stop
docker compose up -d --build
./harbourx.sh docker logs
```

---

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

---

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

---

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

---

## 🔐 安全建议

### ⚠️ 生产环境部署前检查清单

**在部署到生产环境之前，必须完成以下配置：**

1. **✅ 创建 .env 文件**

   ```bash
   cp .env.example .env
   ```

2. **✅ 生成并设置安全的 JWT Secret**

   ```bash
   # 生成安全的 JWT Secret（至少 256 位）
   openssl rand -base64 32

   # 将生成的字符串添加到 .env 文件
   JWT_SECRET=<生成的随机字符串>
   ```

   > ⚠️ **重要**：不要使用默认的 JWT Secret！必须生成新的随机字符串。

3. **✅ 更改数据库密码**

   ```bash
   # 在 .env 文件中设置强密码
   POSTGRES_PASSWORD=<强密码>
   ```

   > ⚠️ **重要**：不要使用默认密码 `harbourx_password`！

4. **✅ 配置所有必需的环境变量**

   - `POSTGRES_DB`、`POSTGRES_USER`、`POSTGRES_PASSWORD`
   - `JWT_SECRET`
   - `FRONTEND_ALLOWED_ORIGINS`（根据实际域名调整）

5. **✅ 验证 .env 文件**
   - 确保所有敏感信息都已设置
   - 确保没有使用默认值
   - 确保 `.env` 文件在 `.gitignore` 中（不会被提交到版本控制）

### 生产环境安全最佳实践

1. **更改默认密码**：所有默认密码必须更改
2. **使用强 JWT Secret**：使用 `openssl rand -base64 32` 生成
3. **限制端口暴露**：只暴露必要的端口
4. **使用 HTTPS**：配置反向代理（如 Nginx）和 SSL 证书
5. **定期备份**：设置数据库自动备份
6. **资源限制**：已配置 CPU 和内存限制（见 `docker-compose.yml`）
7. **日志轮转**：已配置日志轮转，防止日志无限增长
8. **非 root 用户**：所有服务以非 root 用户运行

### 环境变量安全

- **不要将 `.env` 文件提交到版本控制**
- 使用 Docker secrets 或外部密钥管理服务（如 AWS Secrets Manager）
- 定期轮换敏感信息（JWT Secret、数据库密码等）
- 使用不同的密码和密钥用于不同环境（开发、测试、生产）

---

## 📝 开发环境

开发环境配置（`docker-compose.dev.yml`）提供：

- **热重载**：代码更改自动重新加载
- **开发工具**：Swagger UI、H2 Console 等
- **调试支持**：可以附加调试器

启动开发环境：

```bash
docker compose -f docker-compose.dev.yml up -d
```

---

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

---

## 📁 项目结构

```
项目根目录/
├── harbourX/                  # Docker 配置文件
│   ├── docker-compose.yml     # 生产环境配置
│   ├── docker-compose.dev.yml # 开发环境配置
│   ├── dockerfiles/           # Dockerfile 目录
│   │   ├── backend/
│   │   ├── frontend/
│   │   └── ai-module/
│   ├── harbourx.sh           # 统一管理脚本（所有操作）
│   ├── .env.example           # 环境变量示例
│   └── README.md              # 本文件
├── HarbourX-Backend/          # Spring Boot 后端
├── HarbourX-Frontend/         # React 前端
└── AI-Module/                 # Node.js AI 服务
```

> 💡 **注意**：项目结构是可移植的。`harbourX` 文件夹应该与三个服务文件夹（`HarbourX-Backend`、`HarbourX-Frontend`、`AI-Module`）在同一父目录下。可以通过 `.env` 文件自定义目录名称。

---

## 🌐 AWS EC2 部署

### 快速部署

#### 方法 1：使用统一管理脚本（推荐）

```bash
# 1. 设置环境变量（可选，脚本有默认值）
export EC2_HOST=13.54.207.94
export EC2_USER=ec2-user
export SSH_KEY=~/.ssh/harbourX-demo-key-pair.pem

# 2. 确保 PEM 文件权限正确
chmod 400 ~/.ssh/harbourX-demo-key-pair.pem

# 3. 部署到 EC2
cd harbourX
./harbourx.sh deploy deploy
```

#### 方法 2：获取 EC2 IP 并部署

```bash
# 获取 EC2 公共 IP
./harbourx.sh deploy ip

# 或使用 AWS CLI
aws ec2 describe-instances \
  --instance-ids i-0a47d93520b410e85 \
  --region ap-southeast-2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text

# 设置并部署
export EC2_HOST=<你的公共IP>
./harbourx.sh deploy deploy
```

#### 其他部署相关命令

```bash
# SSH 连接到 EC2
./harbourx.sh deploy ssh

# 在 EC2 上设置 Git 仓库
./harbourx.sh deploy setup-git

# 在云端创建 Broker
./harbourx.sh deploy create-broker

# 查看当前配置
./harbourx.sh config env
```

### EC2 实例信息

- **实例 ID**: `i-0a47d93520b410e85`
- **公网 IP**: `13.54.207.94`
- **区域**: `ap-southeast-2` (Sydney)
- **用户**: `ec2-user`

### 手动部署步骤

#### 步骤 1：准备 EC2 实例

```bash
# SSH 连接到 EC2
ssh -i ~/.ssh/harbourX-demo-key-pair.pem ec2-user@13.54.207.94

# 安装 Docker
sudo yum update -y
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 重新登录以应用 docker 组权限
exit
ssh -i ~/.ssh/harbourX-demo-key-pair.pem ec2-user@13.54.207.94
```

#### 步骤 2：上传项目文件

部署脚本会自动处理，或手动执行：

```bash
# 在本地打包项目
cd harbourX
tar -czf harbourx-deploy.tar.gz \
    --exclude='.git' \
    --exclude='node_modules' \
    docker-compose.yml \
    dockerfiles/ \
    harbourx.sh

# 上传到 EC2
scp -i ~/.ssh/harbourX-demo-key-pair.pem harbourx-deploy.tar.gz \
    ec2-user@13.54.207.94:/opt/

# SSH 到 EC2 并解压
ssh -i ~/.ssh/harbourX-demo-key-pair.pem ec2-user@13.54.207.94
sudo mkdir -p /opt/harbourx
sudo tar -xzf /opt/harbourx-deploy.tar.gz -C /opt/harbourx
sudo chown -R ec2-user:ec2-user /opt/harbourx
cd /opt/harbourx
```

#### 步骤 3：配置环境变量

```bash
# 在 EC2 上创建 .env 文件
cd /opt/harbourx
cat > .env << 'EOF'
JWT_SECRET=your-super-secret-jwt-key-change-this
DB_IP=postgres
DB_PORT=5432
DB_USER=harbourx
DB_PASS=harbourx_password
FRONTEND_ALLOWED_ORIGINS=http://13.54.207.94
EOF

# 配置 AI-Module 环境变量
cd /opt/AI-Module
cat > .env << 'EOF'
GOOGLE_AI_API_KEY=your_google_ai_api_key
OPENAI_API_KEY=your_openai_api_key
PORT=3000
HOST=0.0.0.0
NODE_ENV=production
EOF
```

#### 步骤 4：启动服务

```bash
cd /opt/harbourx
docker compose up -d --build

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f
```

### 安全组配置

确保 EC2 安全组已配置以下端口：

| 端口 | 协议 | 说明            | 来源             |
| ---- | ---- | --------------- | ---------------- |
| 22   | TCP  | SSH             | 你的 IP 地址     |
| 80   | TCP  | HTTP (Frontend) | 0.0.0.0/0        |
| 8080 | TCP  | Backend API     | 0.0.0.0/0        |
| 3000 | TCP  | AI Module       | 0.0.0.0/0        |
| 5433 | TCP  | PostgreSQL      | 可选，仅内部访问 |

### EC2 访问地址

部署成功后，可以通过以下地址访问：

- **Frontend**: `http://13.54.207.94/`
- **Backend API**: `http://13.54.207.94:8080`
- **Backend Swagger**: `http://13.54.207.94:8080/swagger-ui.html`
- **AI Module**: `http://13.54.207.94:3000`
- **AI Health**: `http://13.54.207.94:3000/health`

### EC2 常用操作

```bash
# SSH 到 EC2
ssh -i ~/.ssh/harbourX-demo-key-pair.pem ec2-user@13.54.207.94

# 查看服务状态
cd /opt/harbourx
docker compose ps

# 查看日志
docker compose logs -f [service-name]

# 重启服务
docker compose restart [service-name]

# 更新服务
cd /opt/harbourx
docker compose down
cd /opt/HarbourX-Frontend  # 或 Backend/AI-Module
git pull
cd /opt/harbourx
docker compose up -d --build
```

---

## 🔄 CI/CD 工作流程

### 概述

HarbourX 项目使用 **GitHub Actions** 实现 CI/CD，包含三个服务：

- **Frontend** (React + Vite)
- **Backend** (Spring Boot)
- **AI-Module** (Node.js + Express)

### CI (Continuous Integration) - 持续集成

#### 触发条件

1. **Pull Request** - 创建或更新 PR 时自动触发
2. **Push 到分支** - Push 到 main, develop, feature/**, ci/** 分支
3. **手动触发** - 通过 `workflow_dispatch` 手动运行

#### Frontend CI 流程

```yaml
触发: PR 创建/更新 或 Push 到分支
↓
并行执行 4 个 Job:
├── 1. Lint & Code Quality
│   ├── 安装依赖 (npm ci)
│   ├── ESLint 代码检查
│   ├── 检查未使用的依赖
│   └── 安全漏洞扫描 (npm audit)
│
├── 2. TypeScript Type Check
│   ├── 安装依赖
│   └── TypeScript 类型检查 (tsc --noEmit)
│
├── 3. Build Application
│   ├── 安装依赖
│   ├── 构建项目 (npm run build)
│   ├── 上传构建产物
│   └── 分析构建大小
│
└── 4. Run Tests
    ├── 安装依赖
    ├── 运行测试并生成覆盖率 (npm run test:coverage)
    ├── 上传覆盖率报告到 Codecov
    └── 在 PR 中评论覆盖率
```

#### Backend CI 流程

```yaml
触发: PR 创建/更新 或 手动触发
↓
执行 Job:
├── Checkout 代码
├── 设置 JDK 21
├── 运行静态代码检查 (Checkstyle + Spotless)
└── 运行 Maven 验证 (包括测试)
    └── 上传 JaCoCo 覆盖率报告
```

#### AI-Module CI 流程

```yaml
触发: Push 到 main/develop 或 PR
↓
执行 Job:
├── Checkout 代码
├── 设置 Node.js 20
├── 设置 pnpm
├── 安装依赖 (pnpm install --frozen-lockfile)
├── 运行测试 (pnpm test)
├── 构建项目 (pnpm build)
└── 上传构建产物
```

### CD (Continuous Deployment) - 持续部署

#### 触发条件

1. **Push 到 main 分支** - 代码合并到 main 后自动触发
2. **路径过滤** - 只有相关文件变更时才触发
   - Frontend: `HarbourX-Frontend/**`, `harbourX/dockerfiles/frontend/**`
   - Backend: `HarbourX-Backend/**`, `harbourX/dockerfiles/backend/**`
   - AI-Module: `AI-Module/**`, `harbourX/dockerfiles/ai-module/**`
3. **手动触发** - 通过 `workflow_dispatch` 手动部署

#### 部署流程（三个服务相同）

```yaml
触发: Push 到 main (相关路径变更)
↓
执行部署 Job:
├── 1. Checkout 代码
│
├── 2. SSH 连接到 EC2 实例
│   └── 使用 GitHub Secrets:
│       - EC2_HOST (13.54.207.94)
│       - EC2_USER (ec2-user)
│       - EC2_SSH_KEY (SSH 私钥)
│
├── 3. 停止现有服务
│   └── docker-compose stop <service> || true
│
├── 4. 更新代码
│   └── cd /opt/<Service>
│       git fetch origin
│       git reset --hard origin/main
│       git clean -fd
│
├── 5. 重新构建并启动
│   └── cd /opt/harbourx
│       docker-compose up -d --build <service>
│
├── 6. 等待服务启动
│   └── sleep 10-30 秒（根据服务类型）
│
├── 7. 检查服务状态
│   ├── docker-compose ps <service>
│   └── docker-compose logs <service> --tail=20
│
└── 8. 生成部署摘要
    └── 在 GitHub Actions 中显示部署信息
```

#### 三个服务的部署对比

| 服务          | 停止命令                        | 代码目录                 | 等待时间 | 访问地址                   |
| ------------- | ------------------------------- | ------------------------ | -------- | -------------------------- |
| **Frontend**  | `docker-compose stop frontend`  | `/opt/HarbourX-Frontend` | 10 秒    | `http://13.54.207.94/`     |
| **Backend**   | `docker-compose stop backend`   | `/opt/HarbourX-Backend`  | 30 秒    | `http://13.54.207.94:8080` |
| **AI-Module** | `docker-compose stop ai-module` | `/opt/AI-Module`         | 15 秒    | `http://13.54.207.94:3000` |

### 架构图

```
开发者
  │
  ├─→ 创建 Feature Branch
  │     │
  │     └─→ 提交代码
  │           │
  │           └─→ 创建 Pull Request
  │                 │
  │                 └─→ 🔍 CI 自动运行
  │                       ├─→ Lint 检查
  │                       ├─→ Type Check
  │                       ├─→ Build
  │                       └─→ Tests
  │
  └─→ 合并到 main 分支
        │
        └─→ 🚀 CD 自动触发
              │
              └─→ 部署到 EC2
                    │
                    ├─→ 更新代码
                    ├─→ 停止旧服务
                    ├─→ 构建 Docker 镜像
                    └─→ 启动新服务
```

---

## 🔐 GitHub CI/CD 配置

### 配置 GitHub Secrets

**重要**: 需要在**每个仓库**（Frontend、Backend、AI-Module）中分别配置 Secrets。

#### 必需 Secrets

1. **EC2_HOST**: EC2 实例的公网 IP 地址

   - 值: `13.54.207.94`

2. **EC2_USER**: EC2 实例的用户名（可选，默认为 `ec2-user`）

   - Amazon Linux: `ec2-user`
   - Ubuntu: `ubuntu`

3. **EC2_SSH_KEY**: SSH 私钥内容（PEM 文件的完整内容）
   - 获取方式: `cat ~/.ssh/harbourX-demo-key-pair.pem`
   - 复制**整个文件内容**，包括 `-----BEGIN RSA PRIVATE KEY-----` 和 `-----END RSA PRIVATE KEY-----`

#### 配置步骤

**方法 1: 通过 GitHub Web 界面**

1. 进入 GitHub 仓库（例如 `HarbourX-Team/HarbourX-Frontend`）
2. 点击 **Settings** → **Secrets and variables** → **Actions**
3. 点击 **New repository secret**
4. 依次添加三个 secrets：
   - Name: `EC2_HOST`, Value: `13.54.207.94`
   - Name: `EC2_USER`, Value: `ec2-user`（可选）
   - Name: `EC2_SSH_KEY`, Value: `<粘贴完整的 PEM 文件内容>`
5. 重复上述步骤，为其他两个仓库（Backend、AI-Module）也配置相同的 secrets

**方法 2: 使用 GitHub CLI（推荐批量配置）**

```bash
# 为每个仓库配置 secrets
gh secret set EC2_HOST --body "13.54.207.94" --repo HarbourX-Team/HarbourX-Frontend
gh secret set EC2_USER --body "ec2-user" --repo HarbourX-Team/HarbourX-Frontend
gh secret set EC2_SSH_KEY --body "$(cat ~/.ssh/harbourX-demo-key-pair.pem)" --repo HarbourX-Team/HarbourX-Frontend

gh secret set EC2_HOST --body "13.54.207.94" --repo HarbourX-Team/HarbourX-Backend
gh secret set EC2_USER --body "ec2-user" --repo HarbourX-Team/HarbourX-Backend
gh secret set EC2_SSH_KEY --body "$(cat ~/.ssh/harbourX-demo-key-pair.pem)" --repo HarbourX-Team/HarbourX-Backend

gh secret set EC2_HOST --body "13.54.207.94" --repo HaimoneyTeam/AI-Module
gh secret set EC2_USER --body "ec2-user" --repo HaimoneyTeam/AI-Module
gh secret set EC2_SSH_KEY --body "$(cat ~/.ssh/harbourX-demo-key-pair.pem)" --repo HaimoneyTeam/AI-Module
```

### Workflow 文件位置

```
HarbourX-Frontend/
  └── .github/workflows/
      ├── ci.yml    # CI workflow
      └── cd.yml    # CD workflow

HarbourX-Backend/
  └── .github/workflows/
      ├── ci.yml    # CI workflow
      └── cd.yml    # CD workflow

AI-Module/
  └── .github/workflows/
      ├── ci.yml    # CI workflow
      └── cd.yml    # CD workflow
```

### EC2 前置要求

在 EC2 实例上需要：

1. **安装 Git**:

   ```bash
   sudo yum install git -y  # Amazon Linux
   ```

2. **初始化 Git 仓库**:

   运行本地脚本自动设置：

   ```bash
   cd harbourX
   ./harbourx.sh deploy setup-git
   ```

   或手动在 EC2 上执行：

   ```bash
   cd /opt
   sudo git clone https://github.com/HarbourX-Team/HarbourX-Frontend.git
   sudo git clone https://github.com/HarbourX-Team/HarbourX-Backend.git
   sudo git clone https://github.com/HaimoneyTeam/AI-Module.git
   sudo chown -R ec2-user:ec2-user HarbourX-* AI-Module
   ```

3. **配置 Git 访问（如果仓库是私有的）**:

   **选项 A: 使用 Personal Access Token (推荐)**

   ```bash
   # 在 EC2 上为每个仓库配置
   cd /opt/HarbourX-Frontend
   git remote set-url origin https://<YOUR_TOKEN>@github.com/HarbourX-Team/HarbourX-Frontend.git

   cd /opt/HarbourX-Backend
   git remote set-url origin https://<YOUR_TOKEN>@github.com/HarbourX-Team/HarbourX-Backend.git

   cd /opt/AI-Module
   git remote set-url origin https://<YOUR_TOKEN>@github.com/HaimoneyTeam/AI-Module.git
   ```

### 使用说明

#### 自动部署

1. 提交代码到 `main` 分支
2. GitHub Actions 自动触发 CI
3. CI 通过后，CD workflow 自动部署到 EC2

#### 手动部署

1. 进入 GitHub 仓库的 **Actions** 标签页
2. 选择对应的 CD workflow（如 "Frontend CD"）
3. 点击 **Run workflow**
4. 选择分支并点击 **Run workflow**

#### 查看部署状态

- 在 **Actions** 标签页查看 workflow 运行状态
- 点击具体的 workflow run 查看详细日志
- 部署成功后，在 Summary 中查看部署信息

### CI/CD 故障排查

#### CI 失败

1. 检查 GitHub Actions 日志
2. 查看具体的失败步骤
3. 修复问题后重新提交

#### CD 部署失败

1. **检查 Secrets 配置**:

   - 确认 `EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY` 都已正确设置

2. **检查 SSH 连接**:

   - 验证 SSH key 权限和格式
   - 确认 EC2 安全组允许 SSH (端口 22)

3. **检查 EC2 资源**:

   - 确认磁盘空间充足
   - 检查 Docker 服务是否运行
   - 查看 EC2 上的 docker-compose 日志

4. **检查代码拉取**:
   - 确认仓库是公开的，或已配置访问权限
   - 检查 `/opt/` 目录权限

#### 服务启动失败

1. 查看 GitHub Actions 日志中的错误信息
2. SSH 到 EC2 检查服务状态:
   ```bash
   cd /opt/harbourx
   docker-compose ps
   docker-compose logs <service-name>
   ```

### 工作流程示例

#### 典型开发流程

1. **开发功能**:

   ```bash
   git checkout -b feature/new-feature
   # 开发代码...
   git commit -m "feat: add new feature"
   git push origin feature/new-feature
   ```

2. **创建 PR**:

   - CI workflow 自动运行测试
   - 通过后合并到 `main` 分支

3. **自动部署**:
   - 合并到 `main` 后，CD workflow 自动触发
   - 代码自动部署到 EC2

#### 紧急修复流程

1. **直接修复**:

   ```bash
   git checkout main
   git pull
   # 修复代码...
   git commit -m "fix: urgent fix"
   git push origin main
   ```

2. **自动部署**:
   - CD workflow 自动部署修复

---

## ⚠️ 注意事项

1. **首次启动**：首次启动可能需要几分钟来构建镜像和初始化数据库
2. **数据库数据**：使用 `docker compose down -v` 会删除所有数据库数据
3. **端口冲突**：确保端口 80、8080、3000、5433 未被占用
4. **环境变量**：AI 模块需要 `.env` 文件（在 `AI-Module/.env`）
5. **日志查看**：使用 `Ctrl+C` 退出日志查看模式
6. **路径过滤**：CD 只在相关文件变更时触发，避免不必要的部署
7. **服务启动时间**：Backend 需要 30 秒启动时间（Spring Boot）
8. **数据库迁移**：Backend 部署时会自动运行 Liquibase 迁移

---

## 📚 更多资源

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [AWS EC2 文档](https://docs.aws.amazon.com/ec2/)
- [Spring Boot Docker 指南](https://spring.io/guides/gs/spring-boot-docker/)
- [React Docker 最佳实践](https://mherman.org/blog/dockerizing-a-react-app/)

---

## 📄 License

本项目属于 HarbourX 系统的一部分。
