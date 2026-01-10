# HarbourX Docker 部署指南

> **最后更新**: 2025-01-10  
> **部署方式**: AWS Systems Manager (SSM) Run Command (Staging 环境)  
> **本地开发**: Docker Compose  
> **环境流程**: Dev → Staging (main) → Release (production)

HarbourX 系统的 Docker 化部署配置、CI/CD 流程和 AWS EC2 部署指南。

---

## 📋 目录

- [🚀 快速开始](#-快速开始)
- [🌍 环境管理](#-环境管理)
- [📦 服务说明](#-服务说明)
- [🌐 访问地址](#-访问地址)
- [🔧 常用命令](#-常用命令)
- [🐳 Docker 配置说明](#-docker-配置说明)
- [🔄 CI/CD 部署流程](#-cicd-部署流程)
- [🚀 Staging 环境部署](#-staging-环境部署)
- [🐛 故障排查](#-故障排查)
- [📝 文件说明](#-文件说明)

---

## 🚀 快速开始

### 前置要求

- Docker Desktop 或 Docker Engine 20.10+
- Docker Compose 2.0+
- 至少 4GB 可用内存
- 至少 10GB 可用磁盘空间

### 一键启动

```bash
cd harbourX

# 本地完整部署（推荐首次使用）
./harbourx.sh deploy local          # 本地环境（模拟 staging）
./harbourx.sh deploy local dev      # 开发环境（热重载）

# 或快速启动（已部署过）
./harbourx.sh docker start          # 本地环境
./harbourx.sh docker start:dev      # 开发环境

# 或直接使用 Docker Compose
docker compose up -d                 # 本地环境
docker compose -f docker-compose.dev.yml up -d  # 开发环境
```

### 环境变量配置

> ⚠️ **重要**: 本地开发前，必须配置环境变量

```bash
# 复制环境变量示例文件
cp env.example .env

# 编辑 .env 文件，根据实际情况修改配置
# 注意：.env 文件包含敏感信息，不要提交到 Git
```

**环境变量说明**：
- 参考 `env.example` 文件获取完整的环境变量列表
- 本地开发使用 `docker-compose.yml` 时，需要配置 PostgreSQL、JWT Secret 等
- AI-Module 需要单独的 `.env` 文件：`../AI-Module/.env`
- **Staging 环境部署**通过 GitHub Actions CI/CD 自动处理，配置存储在 EC2 实例的 `/opt/harbourx/.env` 文件中

---

## 🌍 环境管理

### 环境流程 (Dev → Staging → Release)

```
开发环境 (Dev)
    ↓ (Feature Branch PR → main)
Staging 环境 (main 分支自动部署)
    ↓ (Release Branch / Tag)
Production 环境 (Release 版本)
```

### 当前环境配置

| 环境       | 分支/触发          | 部署目标          | Spring Profile      | RDS 实例        |
| ---------- | ------------------ | ----------------- | ------------------- | --------------- |
| **Dev**    | `develop` (计划)   | 本地 Docker       | `base,dev`          | 本地 PostgreSQL |
| **Staging** | `main` (当前)      | EC2 (Staging)     | `staging,rds`       | RDS (Staging)   |
| **Release** | `release/*` (计划) | EC2 (Production)  | `prod,rds`          | RDS (Production)|

### 当前状态

- ✅ **Staging 环境已配置**: main 分支 Push 会自动部署到 Staging 环境
- 🔄 **Dev 环境**: 计划中（develop 分支）
- 🔄 **Production 环境**: 计划中（release 分支或标签触发）

**注意**: 当前所有 main 分支的部署都指向 **Staging 环境**，不再是 Production。

---

## 📦 服务说明

| 服务       | 容器名               | 端口 | 说明                                        |
| ---------- | -------------------- | ---- | ------------------------------------------- |
| PostgreSQL | `harbourx-postgres`  | 5433 | 数据库服务（本地开发）                      |
| Backend    | `harbourx-backend`   | 8080 | Spring Boot API 服务                        |
| AI-Module  | `harbourx-ai-module` | 3000 | AI 分析服务                                 |
| Frontend   | `harbourx-frontend`  | 80   | React + Nginx 前端服务                      |

**注意**: 生产环境使用 Amazon RDS，不包含 PostgreSQL 容器。

### 服务依赖关系

```
Frontend → Backend (API calls)
Frontend → AI-Module (AI analysis)
Backend → PostgreSQL/RDS (Database)
```

---

## 🌐 访问地址

### 本地开发环境

| 服务             | 地址                                  | 说明                      |
| ---------------- | ------------------------------------- | ------------------------- |
| **前端**         | http://localhost                      | 主应用界面                |
| **后端 API**     | http://localhost:8080                 | REST API                  |
| **后端 Swagger** | http://localhost:8080/swagger-ui.html | API 文档                  |
| **AI 模块**      | http://localhost:3000                 | AI 服务                   |
| **AI 健康检查**  | http://localhost:3000/health          | 健康检查                  |
| **PostgreSQL**   | localhost:5433                        | 数据库（容器内使用 5432） |

### 开发环境（热重载）

- **前端**: http://localhost:3001
- **后端**: http://localhost:8080
- **AI 模块**: http://localhost:3000

---

## 🔧 常用命令

### 使用 harbourx.sh 脚本（推荐）

```bash
cd harbourX

# Docker 操作（本地开发）
./harbourx.sh docker start          # 启动所有服务（生产环境）
./harbourx.sh docker start:dev      # 启动开发环境（热重载）
./harbourx.sh docker stop           # 停止所有服务
./harbourx.sh docker restart        # 重启所有服务
./harbourx.sh docker logs backend   # 查看后端日志
./harbourx.sh docker status         # 查看服务状态
./harbourx.sh docker clean          # 清理 Docker 资源（需确认）

# 本地部署操作
./harbourx.sh deploy local          # 本地完整部署
./harbourx.sh deploy local dev      # 本地开发环境部署

# 生产环境部署（手动方式，独立于 CI/CD）
./harbourx.sh deploy backend        # 手动部署后端到 EC2
./harbourx.sh deploy frontend       # 手动部署前端到 EC2
# 或使用 CI/CD（推荐）:
# Backend: Push 到 main 分支，触发 .github/workflows/cd.yml
# Frontend: Push 到 main 分支，触发 .github/workflows/CD.yml

# 调试工具
./harbourx.sh deploy ssh            # SSH 连接到 EC2 实例
./harbourx.sh deploy ip             # 获取 EC2 实例 IP 地址

# 帮助信息
./harbourx.sh help                  # 查看完整帮助
./harbourx.sh config env            # 查看配置
```

### 直接使用 Docker Compose

```bash
cd harbourX

# 生产环境
docker compose up -d                 # 启动所有服务
docker compose down                  # 停止所有服务
docker compose logs -f backend       # 查看后端日志
docker compose ps                    # 查看服务状态

# 开发环境（热重载）
docker compose -f docker-compose.dev.yml up -d
docker compose -f docker-compose.dev.yml logs -f
docker compose -f docker-compose.dev.yml down
```

---

## 🐳 Docker 配置说明

### Docker Compose 文件

#### 1. `docker-compose.yml` - 生产环境配置 ✅

**用途**: 本地完整环境（包含所有服务）

**包含服务**:
- `postgres` - PostgreSQL 数据库
- `backend` - Spring Boot 后端
- `ai-module` - AI 分析模块
- `frontend` - React 前端 (Nginx)

**使用场景**:
- 本地完整环境测试
- 生产环境模拟
- `./harbourx.sh docker start`

**网络配置**:
- 网络名: `harbourx-network` (外部可见)
- 所有容器在同一网络中，可通过容器名访问

#### 2. `docker-compose.dev.yml` - 开发环境配置 ✅

**用途**: 本地开发环境（热重载）

**特点**:
- 使用 volumes 挂载源代码
- 支持代码热重载
- 快速重启和调试

**使用场景**:
- 本地开发调试
- `./harbourx.sh docker start:dev`

**网络配置**:
- 网络名: `harbourx-network-dev` (与 Staging 环境隔离)

#### 3. `docker-compose.prod.yml` / `docker-compose.staging.yml` - EC2 Staging 配置 ⚠️

**用途**: EC2 Staging 环境配置模板（参考）

**注意**: 
- ⚠️ **CD 工作流会自动生成 `docker-compose.staging.yml`**，本地文件主要用于参考
- 实际部署时由 GitHub Actions 工作流自动生成到 EC2
- 如需修改 Staging 配置，请更新 `HarbourX-Backend/.github/workflows/cd.yml`
- **当前 main 分支部署到 Staging 环境**（不再是 Production）

**包含服务**:
- `backend` - Spring Boot 后端（连接 RDS）
- 不包含 `postgres`（使用 Amazon RDS）

### Dockerfile 文件

#### Backend Dockerfile
- **位置**: `dockerfiles/backend/Dockerfile`
- **用途**: 构建后端 Spring Boot 镜像
- **使用**: GitHub Actions CD 工作流 + 本地构建

#### Frontend Dockerfile
- **位置**: `dockerfiles/frontend/Dockerfile`
- **用途**: 构建前端 React 镜像（生产环境）
- **特点**: 多阶段构建，包含 Nginx 配置
- **nginx.conf**: 使用 `HarbourX-Frontend/app/src/infrastructure/docker/nginx.conf`

#### Frontend Dev Dockerfile
- **位置**: `dockerfiles/frontend/Dockerfile.dev`
- **用途**: 构建前端开发镜像（热重载）
- **使用**: `docker-compose.dev.yml`

#### AI Module Dockerfile
- **位置**: `dockerfiles/ai-module/Dockerfile`
- **用途**: 构建 AI 分析模块镜像
- **使用**: `docker-compose.yml`

### 网络配置统一化

**问题**: 不同 docker-compose 文件创建的容器在不同网络中，无法通信

**解决方案**: 在所有 docker-compose 文件中明确指定网络名

```yaml
networks:
  harbourx-network:
    driver: bridge
    name: harbourx-network  # ✅ 明确指定网络名
```

**效果**:
- ✅ 所有容器在同一网络中
- ✅ 容器可以通过容器名互相访问
- ✅ 前端可以通过 `harbourx-backend` 访问后端

### Nginx 配置

**实际使用**: `HarbourX-Frontend/app/src/infrastructure/docker/nginx.conf`

**关键配置**:
- 使用容器名（而不是服务名）进行代理
- 延迟 DNS 解析（使用变量）
- 显式传递 Authorization header
- CORS 配置

**代理规则**:
- `/api/` → `harbourx-backend:8080` (后端 API)
- `/api/ai/` → `harbourx-ai-module:3000` (AI 模块)

---

## 🔄 CI/CD 部署流程

### ⚠️ 重要：Staging 环境部署方式

**Backend 和 Frontend 已配置 CI/CD，main 分支 Push 会自动部署到 Staging 环境。同时提供独立的手动部署命令作为备用方案。**

### 部署架构（Staging 环境）

```
本地开发 (docker-compose)
    ↓
开发者 Push 代码到 main 分支
    ↓
GitHub Actions 自动触发 CD 工作流
    ↓
构建 Docker 镜像 → 推送到 Amazon ECR
    ↓
AWS SSM (Backend) / SSH (Frontend) 自动部署
    ↓
EC2 Instance (Staging 环境)
    ↓
Amazon RDS (Staging 数据库)
```

### 环境流程说明

- **main 分支** → 自动部署到 **Staging 环境**（当前配置）
- **release 分支** → 部署到 **Production 环境**（计划中）
- **develop 分支** → 部署到 **Dev 环境**（计划中）

### 部署方式对比

#### 方式 1: GitHub Actions CI/CD（推荐，自动部署）

**Backend (HarbourX-Backend)**:
- **工作流**: `.github/workflows/cd.yml` (Staging)
- **触发**: Push 到 `main` 分支（修改 `src/**`, `pom.xml`, `Dockerfile` 等）
- **部署目标**: Staging 环境 (EC2 + RDS)
- **Spring Profile**: `staging,rds`
- **部署方式**: AWS Systems Manager (SSM) Run Command
- **认证**: IAM OIDC（无需 SSH 密钥）
- **优势**: 自动化、可追溯、符合最佳实践

**Frontend (HarbourX-Frontend)**:
- **工作流**: `.github/workflows/CD.yml` (Staging)
- **触发**: Push 到 `main` 分支（修改 `app/**` 等）
- **部署目标**: Staging 环境 (EC2)
- **部署方式**: SSH 部署到 EC2
- **认证**: GitHub Secrets (EC2_SSH_KEY)
- **优势**: 自动化、版本控制、一键部署

#### 方式 2: 手动独立部署（备用方案）

**后端部署命令**: `./harbourx.sh deploy backend`

**前端部署命令**: `./harbourx.sh deploy frontend`

**特点**:
- ✅ **独立于 CI/CD**，作为备用方案，不会与 CI/CD 冲突
- ✅ **独立部署**：可以单独部署 Backend 或 Frontend
- ✅ **灵活性**：适用于紧急修复、调试、CI/CD 不可用
- ✅ **与 CI/CD 并行**：两种方式可以并存，根据情况选择

**后端部署（deploy backend）**:
- 部署 Backend 服务到 EC2
- 会重置数据库（删除并重新创建）
- 需要 GitHub 认证和 SSH 密钥

**前端部署（deploy frontend）**:
- 部署 Frontend 服务到 EC2
- 不会影响 Backend 服务
- 需要 GitHub 认证和 SSH 密钥

**使用场景**:
- CI/CD 工作流不可用时（GitHub Actions 故障、网络问题等）
- 需要紧急修复或快速部署单个服务（不等待 CI/CD 流程）
- 调试和测试环境配置（快速验证更改）
- 开发环境快速验证（本地测试后的快速部署）
- 只需要更新后端或前端其中一个服务时

**前置要求**:
- GitHub 认证（GITHUB_TOKEN 环境变量或 `gh auth login`）
- SSH 密钥（用于连接 EC2）
- EC2 访问权限

**已废弃的命令**:
- ⚠️ `./harbourx.sh deploy deploy` - 已废弃，请使用 `deploy backend` 和 `deploy frontend`

### 部署方式演进

**之前 (SSH 方式)**:
- ❌ 使用 SSH 密钥连接到 EC2
- ❌ 需要手动管理 SSH 密钥和 GitHub Secrets
- ❌ 安全性较低，不符合 AWS 最佳实践

**现在 (SSM 方式)**:
- ✅ 使用 AWS Systems Manager (SSM) Run Command
- ✅ 通过 IAM OIDC 认证（无需 SSH 密钥）
- ✅ 符合 AWS 安全最佳实践
- ✅ 更可靠、更安全

### Backend CD 工作流

#### 触发条件

**自动触发**:
- Push 到 `main` 分支
- 修改路径包含: `src/**`, `pom.xml`, `Dockerfile`, `.github/workflows/cd.yml`

**手动触发**:
- 在 GitHub Actions 页面点击 "Run workflow"
- 可指定自定义镜像标签

#### 执行流程

```
1. 代码 Push → 触发 CD 工作流
   ↓
2. 构建 Docker 镜像 (tagged + latest)
   ↓
3. 推送到 Amazon ECR
   ↓
4. IAM OIDC 认证 → GitHub Actions 认证到 AWS ✅
   ↓
5. 查找 EC2 实例 ID (通过 Tag 或 Secret)
   ↓
6. 通过 SSM SendCommand 发送部署脚本 ✅
   ↓
7. EC2 执行远程脚本:
   - ECR 登录
   - 拉取最新镜像
   - 数据库迁移 (带锁，防止并发)
   - 自动生成 docker-compose.staging.yml ✅
   - 更新 .env 文件 (ECR_REGISTRY, ECR_REPOSITORY, IMAGE_TAG)
   - 自动安装 docker-compose (如果不存在) ✅
   - 停止旧容器
   - 启动新容器 (docker-compose 或 docker run 回退)
   - 健康检查 (最多 24 次，每次间隔 5 秒)
   ↓
8. 等待 SSM 命令完成 → 获取执行结果
   ↓
9. 验证部署成功
```

#### 关键特性

**1. 自动生成 docker-compose.staging.yml**
- ✅ 配置在 GitHub Actions 工作流中（版本控制）
- ✅ 每次部署自动生成最新配置
- ✅ 无需手动在 EC2 上创建或更新文件

**2. 自动安装 docker-compose**
- ✅ 如果 EC2 上没有 docker-compose，自动下载安装 v2.27.0
- ✅ 支持 curl 和 wget
- ✅ 安装后验证可用性

**3. 智能回退机制**
- ✅ 如果 docker-compose 失败，自动回退到 docker run
- ✅ 使用相同的配置参数
- ✅ 确保部署成功

**4. 迁移锁机制**
- ✅ 使用 flock 防止并发迁移
- ✅ 如果另一个迁移正在运行，会失败并提示

### IAM 配置

#### GitHub Actions IAM Role

**角色名**: `github-actions-harbourx-backend-cd`

**权限**:
- `ssm:SendCommand` - 发送命令到 EC2
- `ssm:GetCommandInvocation` - 获取命令执行结果
- `ssm:ListCommandInvocations` - 列出命令执行
- `ec2:DescribeInstances` - 查找 EC2 实例
- `ecr:*` - ECR 推送和拉取权限
- `logs:*` - CloudWatch 日志权限

#### EC2 Instance Profile

**权限**:
- `ecr:GetAuthorizationToken` - ECR 登录
- `ecr:BatchGetImage` - 拉取镜像
- `ecr:GetDownloadUrlForLayer` - 下载镜像层

---

## 🚀 Staging 环境部署

> **当前配置**: main 分支自动部署到 Staging 环境

### EC2 环境要求（Staging）

#### 必需配置

1. **IAM Instance Profile**
   - 附加到 EC2 实例（Staging）
   - 包含 ECR 拉取权限

2. **SSM Agent**
   - 已安装并运行
   - 允许通过 SSM 执行命令

3. **.env 文件** (`/opt/harbourx/.env`)
   ```bash
   # 数据库配置 (RDS - Staging)
   DB_RDS_ENDPOINT=your-rds-staging-endpoint.rds.amazonaws.com
   DB_RDS_PORT=5432
   DB_RDS_DATABASE=harbourx
   DB_RDS_USERNAME=your_db_user
   DB_RDS_PASSWORD=your_db_password
   
   # 应用配置
   SPRING_PROFILES_ACTIVE=staging,rds
   JWT_SECRET=your_jwt_secret
   
   # ECR 配置 (部署时自动更新)
   ECR_REGISTRY=869894983085.dkr.ecr.ap-southeast-2.amazonaws.com
   ECR_REPOSITORY=harbourx-backend
   IMAGE_TAG=latest
   ```

4. **目录结构**
   ```
   /opt/harbourx/
   ├── .env                      # 必需，手动创建（包含敏感信息）
   └── docker-compose.staging.yml # 自动生成（CD 工作流）
   ```

### 首次部署（Staging）

#### 1. 创建 .env 文件（手动）

```bash
# 通过 SSM Session Manager 或保留的 SSH 访问 EC2 (Staging)
cd /opt/harbourx

# 创建 .env 文件（包含所有敏感信息）
cat > .env << 'EOF'
DB_RDS_ENDPOINT=your-rds-staging-endpoint.rds.amazonaws.com
DB_RDS_PORT=5432
DB_RDS_DATABASE=harbourx
DB_RDS_USERNAME=your_db_user
DB_RDS_PASSWORD=your_db_password
JWT_SECRET=your_jwt_secret
SPRING_PROFILES_ACTIVE=staging,rds
EOF
```

#### 2. 执行 CD 工作流（自动触发）

- Push 代码到 `main` 分支（自动部署到 Staging），或
- 在 GitHub Actions 页面手动触发 "Continuous Deployment" 工作流

#### 3. 验证部署（Staging）

```bash
# 通过 SSM Session Manager 访问 EC2 (Staging)
cd /opt/harbourx

# 检查容器状态
docker ps | grep harbourx-backend

# 检查健康状态
curl http://localhost:8080/actuator/health

# 查看容器日志
docker logs harbourx-backend --tail=50 -f
```

### 后续部署（Staging）

- ✅ **完全自动化**: 只需 Push 代码到 `main` 分支
- ✅ **CD 工作流自动执行**（Staging 环境）:
  - 构建镜像 → 推送到 ECR
  - 通过 SSM 自动部署到 EC2
  - 自动生成 docker-compose.staging.yml
  - 自动安装 docker-compose（如果不存在）
  - 执行数据库迁移
  - 更新容器
  - 健康检查

---

## 🐛 故障排查

### 常见问题

#### 1. SSM 命令执行失败

**症状**: `Command failed with status: Failed`

**排查步骤**:
```bash
# 查看 GitHub Actions 日志中的错误信息
# 在 "Deploy to EC2 via SSM" 步骤中查看 StandardErrorContent

# 查看 CloudWatch 日志
aws logs tail /aws/ssm/harbourx-backend-deploy --follow

# 检查 EC2 实例的 SSM Agent 状态
aws ssm describe-instance-information \
  --instance-information-filter-list key=InstanceIds,valueSet=i-xxx
```

**可能原因**:
- EC2 实例未安装/启用 SSM Agent
- IAM Instance Profile 权限不足
- 网络连接问题
- 远程脚本执行错误

#### 2. docker-compose 命令失败

**症状**: `unknown shorthand flag: 'f' in -f`

**解决方案**:
- ✅ **已实现**: 自动安装 docker-compose（如果不存在）
- ✅ **已实现**: 回退到 docker run（如果 docker-compose 失败）

**手动修复** (如果需要):
```bash
# 通过 SSM Session Manager 访问 EC2
cd /opt/harbourx

# 手动安装 docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

#### 3. 健康检查失败

**症状**: `Health check timeout`

**排查步骤**:
```bash
# 检查容器状态
docker ps -a | grep harbourx-backend

# 检查容器日志
docker logs harbourx-backend --tail=200

# 手动测试健康检查
curl http://localhost:8080/actuator/health

# 检查数据库连接
docker exec harbourx-backend env | grep DB_
```

**可能原因**:
- 应用启动失败
- 数据库连接问题
- 端口冲突
- 内存不足
- 环境变量配置错误

#### 4. IAM OIDC 认证失败

**症状**: `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**排查步骤**:
1. 检查 IAM Role Trust Policy 是否正确配置
2. 检查 OIDC Provider 是否存在
3. 验证 GitHub 仓库路径是否匹配

**修复**: 参考 `HarbourX-Backend/scripts/fix-oidc-trust-policy.sh`

#### 5. ECR 拉取失败

**症状**: `Error response from daemon: pull access denied`

**排查步骤**:
- 检查 EC2 Instance Profile 是否有 ECR 权限
- 检查 ECR 镜像是否存在
- 检查网络连接（EC2 能否访问 ECR）

#### 6. 数据库迁移失败

**症状**: `Migration failed` 或 `Another migration is running`

**排查步骤**:
```bash
# 检查迁移锁文件
ls -la /tmp/harbourx_migrate.lock

# 如果锁文件存在，可以手动删除（谨慎操作）
rm /tmp/harbourx_migrate.lock

# 检查数据库连接
docker exec harbourx-backend env | grep DB_
```

### 日志位置

**GitHub Actions 日志**:
- 在 GitHub Actions 页面查看完整日志
- 包括构建、推送、部署各个阶段的输出

**CloudWatch 日志**:
- Log Group: `/aws/ssm/harbourx-backend-deploy`
- 包含 SSM 命令的完整输出和错误信息

**EC2 容器日志**:
```bash
# 通过 SSM Session Manager 访问 EC2
docker logs harbourx-backend --tail=200 -f
```

### 快速验证命令

```bash
# 在 EC2 上执行（通过 SSM Session Manager）
cd /opt/harbourx

echo "=== 文件检查 ==="
[ -f "docker-compose.staging.yml" ] && echo "✅ docker-compose.staging.yml 存在" || echo "❌ 不存在"
[ -f ".env" ] && echo "✅ .env 文件存在" || echo "❌ 不存在"

echo "=== docker-compose 检查 ==="
command -v docker-compose >/dev/null 2>&1 && echo "✅ docker-compose 已安装" || echo "❌ 未安装"

echo "=== 容器检查 ==="
docker ps | grep harbourx-backend && echo "✅ 容器运行中" || echo "❌ 容器未运行"

echo "=== 健康检查 ==="
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health 2>/dev/null || echo "000")
if [ "$HEALTH" = "200" ] || [ "$HEALTH" = "401" ] || [ "$HEALTH" = "403" ]; then
  echo "✅ 健康检查通过 (HTTP $HEALTH)"
else
  echo "❌ 健康检查失败 (HTTP $HEALTH)"
fi
```

---

## 📝 文件说明

### ✅ 必需文件

#### Docker Compose 配置文件

**`docker-compose.yml`** ✅
- **用途**: 本地开发/生产环境测试
- **包含**: postgres, backend, ai-module, frontend
- **使用**: `./harbourx.sh docker start` 或 `docker compose up -d`

**`docker-compose.dev.yml`** ✅
- **用途**: 本地开发环境（热重载）
- **包含**: 所有服务，使用 volumes 挂载源代码
- **使用**: `./harbourx.sh docker start:dev`

**`docker-compose.prod.yml`** ⚠️ **可选（参考）**
- **用途**: EC2 Staging 环境配置模板（参考）
- **注意**: CD 工作流会自动生成 `docker-compose.staging.yml`，本地文件主要用于参考
- **当前环境**: main 分支部署到 Staging，不再是 Production
- **使用**: 手动部署或配置参考

#### Dockerfile 文件

**`dockerfiles/backend/Dockerfile`** ✅
- **用途**: 构建后端镜像
- **使用**: GitHub Actions CD + 本地构建

**`dockerfiles/frontend/Dockerfile`** ✅
- **用途**: 构建前端生产镜像
- **nginx.conf**: 使用 `HarbourX-Frontend/app/src/infrastructure/docker/nginx.conf`
- **使用**: `docker-compose.yml`

**`dockerfiles/frontend/Dockerfile.dev`** ✅
- **用途**: 构建前端开发镜像（热重载）
- **使用**: `docker-compose.dev.yml`

**`dockerfiles/ai-module/Dockerfile`** ✅
- **用途**: 构建 AI 模块镜像
- **使用**: `docker-compose.yml`

#### 脚本文件

**`harbourx.sh`** ✅
- **用途**: 本地 Docker 和部署管理
- **功能**: 
  - Docker 服务管理（启动、停止、日志）
  - 本地部署
  - EC2 部署（SSH 方式，已废弃，建议使用 CD 工作流）

### 文件使用场景

| 文件 | 本地开发 | 本地测试 | EC2 生产 | 说明 |
|------|---------|---------|---------|------|
| `docker-compose.yml` | ✅ | ✅ | ❌ | 本地完整环境 |
| `docker-compose.dev.yml` | ✅ | ❌ | ❌ | 本地开发（热重载） |
| `docker-compose.prod.yml` | ⚠️ | ⚠️ | ✅ | EC2 Staging 配置（参考） |
| `docker-compose.staging.yml` | ❌ | ❌ | ✅ | EC2 Staging 部署（自动生成） |
| `dockerfiles/*/Dockerfile` | ✅ | ✅ | ✅ | 构建镜像 |

---

## 🎯 最佳实践

### 1. 本地开发

- ✅ 使用 `docker-compose.dev.yml` 进行开发（热重载）
- ✅ 使用 `harbourx.sh` 脚本管理服务
- ✅ 定期清理 Docker 资源（`./harbourx.sh docker clean`）

### 2. 生产部署

- ✅ 使用 GitHub Actions CD 工作流（自动部署）
- ✅ 配置变更通过 Git PR 管理
- ✅ 敏感信息存储在 EC2 .env 文件（不在 Git 中）

### 3. 安全性

- ✅ 使用 IAM OIDC 认证（无需 SSH 密钥）
- ✅ 敏感信息不提交到 Git
- ✅ ECR 访问通过 IAM 控制

### 4. 版本控制

- ✅ 所有配置在 GitHub 仓库中版本控制
- ✅ docker-compose.staging.yml 在工作流中生成，确保一致性
- ✅ 配置变更通过 PR 审查

### 5. 可靠性

- ✅ 自动安装 docker-compose（避免版本问题）
- ✅ 智能回退机制（docker-compose → docker run）
- ✅ 迁移锁机制（防止并发执行）
- ✅ 健康检查验证（确保部署成功）

### 6. 可观测性

- ✅ CloudWatch 日志（SSM 命令执行）
- ✅ GitHub Actions 日志（构建和部署过程）
- ✅ 容器健康检查（应用状态）

---

## 🔗 相关资源

### GitHub 仓库

- **Backend**: https://github.com/HarbourX-Team/HarbourX-Backend
- **Frontend**: https://github.com/HarbourX-Team/HarbourX-Frontend

### AWS 资源

- **ECR Registry**: `869894983085.dkr.ecr.ap-southeast-2.amazonaws.com`
- **ECR Repository**: `harbourx-backend`
- **IAM Role**: `github-actions-harbourx-backend-cd`
- **CloudWatch Log Group**: `/aws/ssm/harbourx-backend-deploy`
- **Region**: `ap-southeast-2`

### 本地管理脚本

- **harbourx.sh**: 本地 Docker 和部署管理脚本
- **使用**: `./harbourx.sh help` 查看所有命令

### 相关文档

- **[migrationScripts/README.md](./migrationScripts/README.md)** - 数据迁移脚本说明

---

## 📝 更新历史

- **2025-01-09**: 
  - 迁移到 SSM 部署方式
  - 移除 SSH 依赖
  - 实现 IAM OIDC 认证
  - 自动生成 docker-compose.staging.yml
  - 自动安装 docker-compose
  - 添加智能回退机制
  - 统一文档结构

---

## 🆘 获取帮助

### 查看帮助信息

```bash
# harbourx.sh 脚本帮助
./harbourx.sh help

# 查看配置
./harbourx.sh config env
```

### 日志查看

```bash
# 查看所有服务日志
./harbourx.sh docker logs

# 查看特定服务日志
./harbourx.sh docker logs backend
./harbourx.sh docker logs frontend

# 使用 Docker Compose
docker compose logs -f backend
```
