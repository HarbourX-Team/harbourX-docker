#!/bin/bash
# HarbourX 统一管理脚本
# 使用方法: ./harbourx.sh <command> [options]

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
EC2_HOST="${EC2_HOST:-13.54.207.94}"
EC2_USER="${EC2_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-~/.ssh/harbourX-demo-key-pair.pem}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
DEPLOY_DIR="/opt/harbourx"

# 辅助函数
echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_cmd() {
    echo -e "${BLUE}[CMD]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
HarbourX 统一管理脚本

用法: ./harbourx.sh <command> [options]

命令:
  docker:
    start         启动 Docker 服务（生产环境）
    start:dev     启动 Docker 服务（开发环境）
    stop          停止 Docker 服务（仅 HarbourX）
    stop:all      停止所有 Docker 容器
    restart       重启 Docker 服务
    logs [service] 查看服务日志（可选服务名）
    status        查看服务状态
    clean         清理所有 Docker 资源（镜像、容器、卷，需要确认）
    clean:all     快速清理所有 Docker 资源（无需确认，谨慎使用）
    copy-env      复制 .env 文件到 AI-Module 目录

  deploy:
    local         本地部署（检查环境、构建并启动所有服务）
    backend       手动部署后端到 EC2 实例（独立于 CI/CD）
    frontend      手动部署前端到 EC2 实例（独立于 CI/CD）
    deploy        ⚠️  已废弃: 请使用 'deploy backend' 和 'deploy frontend'
    ssh           SSH 连接到 EC2 实例（用于调试和手动操作）
    ip            获取 EC2 实例 IP 地址
    setup-git     ⚠️  已废弃: 在 EC2 上设置 Git 仓库，CI/CD 会自动处理
    create-broker 在云端创建 Broker（仅用于测试）

  config:
    env           显示当前配置
    help          显示此帮助信息

环境变量:
  EC2_HOST         EC2 实例 IP 或主机名（默认: 13.54.207.94，用于 SSH 连接）
  EC2_USER         EC2 用户名（默认: ec2-user）
  SSH_KEY          SSH 密钥路径（默认: ~/.ssh/harbourX-demo-key-pair.pem，仅用于调试）
  PROJECT_ROOT     项目根目录（默认: ..）
  BACKEND_DIR      Backend 目录名（默认: HarbourX-Backend）
  FRONTEND_DIR     Frontend 目录名（默认: HarbourX-Frontend）
  AI_MODULE_DIR    AI-Module 目录名（默认: AI-Module）

重要提示:
  ✅  生产环境部署方式：
      - 方式 1（推荐）: Push 代码到 main 分支，GitHub Actions CI/CD 自动部署
      - 方式 2（手动）: 使用 'deploy backend' 或 'deploy frontend' 独立部署到 EC2
  ✅  手动部署命令独立于 CI/CD，可作为备用方案
  ✅  本地开发：使用 'deploy local' 或 'docker start' 命令

示例:
  # 本地开发
  ./harbourx.sh docker start              # 启动本地服务（生产环境）
  ./harbourx.sh docker start:dev          # 启动本地服务（开发环境，热重载）
  ./harbourx.sh docker stop               # 停止 HarbourX 服务
  ./harbourx.sh docker stop:all           # 停止所有 Docker 容器
  ./harbourx.sh docker clean              # 清理 Docker 资源（需确认）
  ./harbourx.sh docker clean:all          # 快速清理所有 Docker 资源
  ./harbourx.sh docker logs backend       # 查看后端日志
  ./harbourx.sh docker copy-env           # 复制 .env 到 AI-Module
  ./harbourx.sh deploy local              # 本地完整部署
  
  # 生产环境部署（手动方式，独立于 CI/CD）
  ./harbourx.sh deploy backend            # 手动部署后端到 EC2
  ./harbourx.sh deploy frontend           # 手动部署前端到 EC2
  # 或使用 CI/CD（推荐）:
  # Backend: Push 到 main 分支，触发 .github/workflows/cd.yml
  # Frontend: Push 到 main 分支，触发 .github/workflows/CD.yml
  
  # 调试工具
  ./harbourx.sh deploy ssh                # SSH 连接到 EC2 实例
  ./harbourx.sh deploy ip                 # 获取 EC2 实例 IP 地址
EOF
}

# Docker 命令
docker_start() {
    local env="${1:-prod}"
    if [ "$env" = "dev" ]; then
        echo_info "启动 Docker 服务（开发环境）..."
        docker compose -f docker-compose.dev.yml up -d
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        echo_info "启动 Docker 服务（生产环境）..."
        docker compose up -d
        COMPOSE_FILE="docker-compose.yml"
    fi
    
    echo ""
    echo_info "等待服务启动..."
    sleep 5
    
    echo ""
    echo_info "服务状态："
    docker compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo_info "启动完成！"
    echo ""
    echo "📋 访问地址："
    if [ "$env" = "dev" ]; then
        echo "  - 前端: http://localhost:3001"
    else
        echo "  - 前端: http://localhost"
    fi
    echo "  - 后端: http://localhost:8080"
    echo "  - AI模块: http://localhost:3000"
    echo ""
    echo "📝 查看日志: ./harbourx.sh docker logs"
}

docker_stop() {
    echo_info "停止 Docker 服务（仅 HarbourX）..."
    
    # 首先尝试使用 docker compose down
    docker compose down --remove-orphans 2>/dev/null || true
    docker compose -f docker-compose.dev.yml down --remove-orphans 2>/dev/null || true
    
    # 检查是否还有 harbourx 相关的容器在运行
    RUNNING_CONTAINERS=$(docker ps --filter "name=harbourx" --format "{{.Names}}" 2>/dev/null || true)
    
    if [ -n "$RUNNING_CONTAINERS" ]; then
        echo_warn "检测到仍有容器在运行，正在强制停止..."
        echo "$RUNNING_CONTAINERS" | while read container; do
            echo "   - 停止容器: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
    fi
    
    # 再次检查
    REMAINING=$(docker ps --filter "name=harbourx" --format "{{.Names}}" 2>/dev/null || true)
    if [ -z "$REMAINING" ]; then
        echo_info "所有 HarbourX 服务已停止"
    else
        echo_warn "以下容器仍在运行:"
        echo "$REMAINING"
    fi
}

docker_stop_all() {
    echo_warn "停止所有 Docker 容器..."
    
    # 获取所有运行中的容器
    RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null || true)
    
    if [ -z "$RUNNING_CONTAINERS" ]; then
        echo_info "没有运行中的容器"
        return 0
    fi
    
    CONTAINER_COUNT=$(echo "$RUNNING_CONTAINERS" | wc -l | tr -d ' ')
    echo_info "发现 $CONTAINER_COUNT 个运行中的容器"
    
    # 停止所有容器
    echo_info "正在停止所有容器..."
    docker stop $RUNNING_CONTAINERS 2>/dev/null || true
    
    # 检查结果
    REMAINING=$(docker ps -q 2>/dev/null || true)
    if [ -z "$REMAINING" ]; then
        echo_info "✅ 所有容器已停止"
    else
        echo_warn "以下容器仍在运行:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
    fi
}

docker_restart() {
    local env="${1:-prod}"
    echo_info "重启 Docker 服务..."
    
    if [ "$env" = "dev" ]; then
        docker compose -f docker-compose.dev.yml restart
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        docker compose restart
        COMPOSE_FILE="docker-compose.yml"
    fi
    
    echo ""
    echo_info "等待服务重启..."
    sleep 5
    
    echo ""
    echo_info "服务状态："
    docker compose -f "$COMPOSE_FILE" ps
    
    echo_info "重启完成！"
}

docker_logs() {
    local service="${1:-}"
    local env="${2:-prod}"
    
    if [ "$env" = "dev" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi
    
    if [ -n "$service" ]; then
        echo_info "查看 $service 服务日志..."
        docker compose -f "$COMPOSE_FILE" logs -f "$service"
    else
        echo_info "查看所有服务日志..."
        docker compose -f "$COMPOSE_FILE" logs -f
    fi
}

docker_status() {
    echo_info "Docker 服务状态："
    echo ""
    docker compose ps 2>/dev/null || echo "生产环境未运行"
    echo ""
    docker compose -f docker-compose.dev.yml ps 2>/dev/null || echo "开发环境未运行"
}

docker_clean() {
    echo_warn "这将删除所有 Docker 镜像、容器和卷！"
    read -p "确认继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "已取消"
        return
    fi
    
    echo_info "停止所有容器..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    echo_info "删除所有容器..."
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    echo_info "删除所有镜像..."
    docker rmi $(docker images -q) -f 2>/dev/null || true
    
    echo_info "清理 Docker 系统..."
    docker system prune -a --volumes -f
    
    echo_info "清理完成！"
}

docker_clean_all() {
    echo_error "⚠️  警告：这将删除所有 Docker 资源（容器、镜像、卷、网络）！"
    echo_error "⚠️  此操作不可恢复！"
    echo ""
    
    # 显示当前资源统计
    echo_info "当前 Docker 资源统计："
    docker system df
    
    echo ""
    echo_warn "即将执行以下操作："
    echo "  1. 停止所有运行中的容器"
    echo "  2. 删除所有容器"
    echo "  3. 删除所有镜像"
    echo "  4. 删除所有卷"
    echo "  5. 删除所有未使用的网络"
    echo "  6. 清理构建缓存"
    echo ""
    
    # 即使快速模式也等待 3 秒
    echo_warn "3 秒后开始清理..."
    sleep 3
    
    echo_info "停止所有容器..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    echo_info "删除所有容器..."
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    echo_info "删除所有镜像..."
    docker rmi $(docker images -aq) -f 2>/dev/null || true
    
    echo_info "删除所有卷..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    
    echo_info "清理 Docker 系统（包括未使用的网络和构建缓存）..."
    docker system prune -a --volumes -f
    
    echo ""
    echo_info "✅ 清理完成！"
    echo ""
    echo_info "清理后的资源统计："
    docker system df
}

# 本地部署命令
deploy_local() {
    local env="${1:-prod}"
    local rebuild="${2:-true}"
    
    echo_info "开始本地部署流程..."
    echo ""
    
    # 1. 检查 Docker
    echo_info "步骤 1/6: 检查 Docker 环境..."
    if ! command -v docker &> /dev/null; then
        echo_error "Docker 未安装，请先安装 Docker"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo_error "Docker 未运行，请启动 Docker Desktop 或 Docker 服务"
        return 1
    fi
    
    echo_info "✅ Docker 环境正常"
    echo ""
    
    # 2. 检查 Docker Compose
    echo_info "步骤 2/6: 检查 Docker Compose..."
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo_error "Docker Compose 未安装"
        return 1
    fi
    echo_info "✅ Docker Compose 可用"
    echo ""
    
    # 3. 检查项目结构
    echo_info "步骤 3/6: 检查项目结构..."
    PROJECT_ROOT="${PROJECT_ROOT:-..}"
    BACKEND_DIR="${BACKEND_DIR:-HarbourX-Backend}"
    FRONTEND_DIR="${FRONTEND_DIR:-HarbourX-Frontend}"
    AI_MODULE_DIR="${AI_MODULE_DIR:-AI-Module}"
    
    if [ ! -d "$PROJECT_ROOT/$BACKEND_DIR" ]; then
        echo_error "Backend 目录不存在: $PROJECT_ROOT/$BACKEND_DIR"
        return 1
    fi
    
    if [ ! -d "$PROJECT_ROOT/$FRONTEND_DIR" ]; then
        echo_error "Frontend 目录不存在: $PROJECT_ROOT/$FRONTEND_DIR"
        return 1
    fi
    
    if [ ! -d "$PROJECT_ROOT/$AI_MODULE_DIR" ]; then
        echo_error "AI-Module 目录不存在: $PROJECT_ROOT/$AI_MODULE_DIR"
        return 1
    fi
    
    echo_info "✅ 项目结构完整"
    echo ""
    
    # 4. 检查环境变量文件
    echo_info "步骤 4/6: 检查环境变量..."
    if [ -f "$PROJECT_ROOT/$AI_MODULE_DIR/.env" ]; then
        echo_info "✅ AI-Module .env 文件存在"
    else
        echo_warn "⚠️  AI-Module .env 文件不存在，某些功能可能无法使用"
        echo_warn "   请确保 $PROJECT_ROOT/$AI_MODULE_DIR/.env 包含必要的 API keys"
    fi
    echo ""
    
    # 5. 停止现有服务
    echo_info "步骤 5/6: 停止现有服务..."
    docker_stop
    echo ""
    
    # 6. 构建并启动服务
    echo_info "步骤 6/6: 构建并启动服务..."
    if [ "$env" = "dev" ]; then
        echo_info "使用开发环境配置..."
        if [ "$rebuild" = "true" ]; then
            docker compose -f docker-compose.dev.yml up -d --build
        else
            docker compose -f docker-compose.dev.yml up -d
        fi
        COMPOSE_FILE="docker-compose.dev.yml"
        FRONTEND_URL="http://localhost:3001"
    else
        echo_info "使用生产环境配置..."
        if [ "$rebuild" = "true" ]; then
            docker compose up -d --build
        else
            docker compose up -d
        fi
        COMPOSE_FILE="docker-compose.yml"
        FRONTEND_URL="http://localhost"
    fi
    
    echo ""
    echo_info "等待服务启动..."
    sleep 10
    
    # 7. 检查服务状态
    echo ""
    echo_info "检查服务状态..."
    docker compose -f "$COMPOSE_FILE" ps
    
    # 8. 健康检查
    echo ""
    echo_info "执行健康检查..."
    
    # 检查 Backend
    echo -n "  Backend (http://localhost:8080): "
    if curl -s -f http://localhost:8080/ > /dev/null 2>&1 || curl -s -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
        echo_info "✅ 运行中"
    else
        echo_warn "⚠️  可能还在启动中..."
    fi
    
    # 检查 AI-Module
    echo -n "  AI-Module (http://localhost:3000/health): "
    if curl -s -f http://localhost:3000/health > /dev/null 2>&1; then
        echo_info "✅ 运行中"
    else
        echo_warn "⚠️  可能还在启动中..."
    fi
    
    # 检查 Frontend
    echo -n "  Frontend ($FRONTEND_URL): "
    if curl -s -f "$FRONTEND_URL" > /dev/null 2>&1; then
        echo_info "✅ 运行中"
    else
        echo_warn "⚠️  可能还在启动中..."
    fi
    
    # 9. 显示访问信息
    echo ""
    echo_info "🎉 本地部署完成！"
    echo ""
    echo "📋 访问地址："
    echo "  - 前端:     $FRONTEND_URL"
    echo "  - 后端 API: http://localhost:8080"
    echo "  - Swagger:  http://localhost:8080/swagger-ui.html"
    echo "  - AI模块:   http://localhost:3000"
    echo "  - 数据库:   localhost:5433"
    echo ""
    echo "📝 常用命令："
    echo "  ./harbourx.sh docker logs          # 查看所有日志"
    echo "  ./harbourx.sh docker logs backend   # 查看后端日志"
    echo "  ./harbourx.sh docker status       # 查看服务状态"
    echo "  ./harbourx.sh docker stop          # 停止服务"
    echo ""
    
    # 10. 显示最近的日志
    echo_info "最近的服务日志（最后 10 行）："
    docker compose -f "$COMPOSE_FILE" logs --tail=10
}

# 完整手动部署命令（前后端一起部署）- 已废弃，请使用 deploy backend 和 deploy frontend
deploy_all() {
    echo_warn "⚠️  此命令已废弃！"
    echo_warn ""
    echo_warn "请使用独立的部署命令："
    echo_warn "  ./harbourx.sh deploy backend   # 独立部署后端到 EC2"
    echo_warn "  ./harbourx.sh deploy frontend  # 独立部署前端到 EC2"
    echo ""
    echo_warn "或者使用 GitHub Actions CI/CD 自动部署（推荐）："
    echo_warn "  - Backend: Push 代码到 main 分支，触发 .github/workflows/cd.yml"
    echo_warn "  - Frontend: Push 代码到 main 分支，触发 .github/workflows/CD.yml"
    echo ""
    echo_error "此命令已不再支持，请使用上述替代方案。"
    return 1
}

# 部署命令（已废弃 - 现在使用 deploy backend/frontend）
deploy_deploy() {
    echo_warn "⚠️  此命令已废弃！"
    echo_warn "请使用独立的部署命令："
    echo_warn "  ./harbourx.sh deploy backend   # 部署后端"
    echo_warn "  ./harbourx.sh deploy frontend  # 部署前端"
    echo ""
    echo_warn "或者使用 GitHub Actions CI/CD 自动部署："
    echo_warn "  - Backend: Push 代码到 main 分支，触发 .github/workflows/cd.yml"
    echo_warn "  - Frontend: Push 代码到 main 分支，触发 .github/workflows/CD.yml"
    echo ""
    read -p "是否继续执行废弃的部署命令？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "已取消。请使用 'deploy backend' 和 'deploy frontend' 或 CI/CD。"
        return 0
    fi
    
    echo_info "执行完整部署（前后端一起）..."
    deploy_all
    return $?
}

# 手动部署后端（包括数据库重置）- 独立于 CI/CD
deploy_deploy_backend() {
    echo_info "手动部署后端到 EC2 实例: $EC2_HOST"
    echo_info "注意：这是手动部署方式，独立于 GitHub Actions CI/CD"
    echo_info "⚠️  警告：此操作会删除现有数据库并重新创建！"
    echo ""
    read -p "确认继续部署后端？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "已取消部署。"
        return 0
    fi
    
    # ============================================
    # 1. 优先检测 GitHub 登录（必需）
    # ============================================
    echo_info "步骤 1/5: 检测 GitHub 登录状态..."
    
    GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    GITHUB_AUTH_METHOD=""
    
    # 方法 1: 检查环境变量
    if [ -n "$GITHUB_TOKEN" ]; then
        echo_info "  检测到 GITHUB_TOKEN 环境变量"
        GITHUB_AUTH_METHOD="env"
    else
        # 方法 2: 尝试从 gh CLI 获取 token
        if command -v gh &> /dev/null; then
            echo_info "  尝试使用 GitHub CLI (gh) 获取 token..."
            GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
            if [ -n "$GITHUB_TOKEN" ]; then
                echo_info "  ✅ 从 gh CLI 获取到 token"
                GITHUB_AUTH_METHOD="gh_cli"
            else
                echo_warn "  ⚠️  gh CLI 未登录或 token 无效"
            fi
        else
            echo_warn "  ⚠️  GitHub CLI (gh) 未安装"
        fi
    fi
    
    # 验证 GitHub token 是否有效（复用 deploy_deploy 的验证逻辑）
    if [ -n "$GITHUB_TOKEN" ]; then
        echo_info "  验证 GitHub token 有效性..."
        if command -v curl &> /dev/null; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                https://api.github.com/user 2>/dev/null || echo "000")
            
            if [ "$HTTP_CODE" = "200" ]; then
                GITHUB_USER=$(curl -s \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    https://api.github.com/user 2>/dev/null | grep -o '"login":"[^"]*' | cut -d'"' -f4 || echo "unknown")
                echo_info "  ✅ GitHub token 有效 (用户: $GITHUB_USER)"
                
                # 检查后端仓库访问权限
                REPO_CHECK_BACKEND=$(curl -s -o /dev/null -w "%{http_code}" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    https://api.github.com/repos/HarbourX-Team/HarbourX-Backend 2>/dev/null || echo "000")
                
                if [ "$REPO_CHECK_BACKEND" = "200" ]; then
                    echo_info "  ✅ 有权限访问后端仓库"
                else
                    echo_warn "  ⚠️  无法访问后端仓库 (HTTP $REPO_CHECK_BACKEND)"
                fi
            else
                echo_error "  ❌ GitHub token 无效或已过期 (HTTP $HTTP_CODE)"
                return 1
            fi
        fi
    else
        echo_error "❌ 未检测到 GitHub 认证信息！"
        return 1
    fi
    
    echo_info "✅ GitHub 登录验证通过"
    echo ""
    
    # ============================================
    # 2. 检查 SSH 密钥
    # ============================================
    echo_info "步骤 2/5: 检查 SSH 密钥..."
    if [ ! -f "$SSH_KEY" ]; then
        echo_error "SSH 密钥文件不存在: $SSH_KEY"
        return 1
    fi
    chmod 400 "$SSH_KEY" 2>/dev/null || true
    echo_info "✅ SSH 密钥检查通过"
    echo ""
    
    # ============================================
    # 3. 检查 SSH 连接
    # ============================================
    echo_info "步骤 3/5: 检查 SSH 连接..."
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "echo '连接成功'" > /dev/null 2>&1; then
        echo_error "无法连接到 EC2 实例"
        return 1
    fi
    echo_info "✅ SSH 连接成功"
    echo ""
    
    # ============================================
    # 4. 上传 harbourX 配置（如果需要）
    # ============================================
    echo_info "步骤 4/5: 上传 harbourX 配置..."
    TAR_FILE="/tmp/harbourx-$(date +%s).tar.gz"
    tar -czf "$TAR_FILE" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='target' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.env' \
        --exclude='containerd' \
        --exclude='*.log' \
        --exclude='.DS_Store' \
        --exclude='*.tar.gz' \
        . 2>/dev/null
    
    scp -i "$SSH_KEY" "$TAR_FILE" "${EC2_USER}@${EC2_HOST}:~/"
    rm -f "$TAR_FILE"
    echo_info "✅ 配置已上传"
    echo ""
    
    # ============================================
    # 5. 在 EC2 上部署后端服务
    # ============================================
    echo_info "步骤 5/5: 在 EC2 上部署后端服务..."
    echo_warn "⚠️  将删除现有数据库并重新创建！"
    
    TAR_FILE_BASENAME=$(basename "$TAR_FILE")
    ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "GITHUB_TOKEN='$GITHUB_TOKEN' TAR_FILE_BASENAME='$TAR_FILE_BASENAME' bash -s" << 'EOF'
        set -e
        cd ~
        sudo mkdir -p /opt/harbourx
        sudo tar -xzf "$TAR_FILE_BASENAME" -C /opt/harbourx 2>/dev/null || true
        sudo chown -R $USER:$USER /opt/harbourx
        rm -f "$TAR_FILE_BASENAME"
        
        cd /opt/harbourx
        
        # 检测实际的 docker 配置目录名
        # 当前目录应该就是包含 dockerfiles 的目录
        if [ -d "dockerfiles" ]; then
            # 当前目录就是 docker 配置目录，使用当前目录名
            CURRENT_PWD=$(pwd)
            DOCKER_DIR_NAME=$(basename "$CURRENT_PWD")
            export DOCKER_DIR="$DOCKER_DIR_NAME"
        elif [ -d "harbourX" ] && [ -d "harbourX/dockerfiles" ]; then
            export DOCKER_DIR="harbourX"
        elif [ -d "harbourx" ] && [ -d "harbourx/dockerfiles" ]; then
            export DOCKER_DIR="harbourx"
        else
            # 查找包含 dockerfiles 的目录
            DOCKER_DIR_FOUND=$(find . -maxdepth 2 -type d -name "dockerfiles" -exec dirname {} \; | head -1 | xargs basename 2>/dev/null)
            if [ -n "$DOCKER_DIR_FOUND" ] && [ "$DOCKER_DIR_FOUND" != "." ]; then
                export DOCKER_DIR="$DOCKER_DIR_FOUND"
            else
                export DOCKER_DIR="harbourX"
            fi
        fi
        echo "当前目录: $(pwd)"
        echo "使用 DOCKER_DIR: $DOCKER_DIR"
        echo "检查 dockerfiles 目录: $(ls -la dockerfiles 2>/dev/null | head -3 || echo 'dockerfiles 不存在')"
        
        # 检测 docker compose 命令
        if command -v docker-compose &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker-compose"
        else
            DOCKER_COMPOSE_CMD="docker compose"
        fi
        
        # 停止并移除后端和数据库服务（完全清理）
        echo "停止并移除后端和数据库服务..."
        # 先停止服务
        $DOCKER_COMPOSE_CMD -f docker-compose.yml stop backend postgres 2>/dev/null || true
        # 然后移除容器
        $DOCKER_COMPOSE_CMD -f docker-compose.yml rm -f backend postgres 2>/dev/null || true
        # 额外强制清理，确保容器完全移除（包括可能的遗留容器）
        docker rm -f harbourx-backend harbourx-postgres 2>/dev/null || true
        # 等待容器完全移除
        sleep 1
        
        # ⚠️ 删除数据库卷并重新创建
        echo ""
        echo "⚠️  删除数据库卷并重新创建..."
        echo "  这将删除所有数据库数据！"
        docker volume rm harbourx_postgres_data 2>/dev/null || true
        docker volume ls | grep postgres_data | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
        echo "  ✅ 数据库卷已删除"
        
        # 设置环境变量
        export PROJECT_ROOT=".."
        export DOCKER_DIR="$DOCKER_DIR"
        FRONTEND_ALLOWED_ORIGINS_VAL="${FRONTEND_ALLOWED_ORIGINS:-http://13.54.207.94,http://localhost:3001,http://localhost:80,http://frontend:80}"
        export FRONTEND_ALLOWED_ORIGINS="$FRONTEND_ALLOWED_ORIGINS_VAL"
        export SPRING_APPLICATION_JSON=$(printf '{"frontend":{"allowedOrigins":"%s"}}' "$FRONTEND_ALLOWED_ORIGINS_VAL")
        
        # 加载 .env 文件（如果存在）以获取已有的配置
        # 首先清理 .env 文件中所有包含占位符或循环引用的 AWS_S3 配置
        if [ -f .env ]; then
            echo "清理 .env 文件中的无效 AWS_S3 配置..."
            # 删除所有包含 ${} 占位符的 AWS_S3 配置行
            grep -v "^AWS_S3.*\${" .env > .env.tmp 2>/dev/null || cat .env > .env.tmp
            mv .env.tmp .env
            # 删除所有包含循环引用的 AWS_S3 配置行
            grep -v "^AWS_S3.*AWS_S3" .env > .env.tmp 2>/dev/null || cat .env > .env.tmp
            mv .env.tmp .env
            
            echo "加载 .env 文件中的配置..."
            # 读取 AWS_S3 配置（排除注释和空行，排除包含 ${} 的行）
            AWS_S3_ACCESS_FROM_ENV=$(grep "^AWS_S3_ACCESS=" .env | grep -v "^#" | grep -v "\${" | cut -d'=' -f2- | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
            AWS_S3_SECRET_FROM_ENV=$(grep "^AWS_S3_SECRET=" .env | grep -v "^#" | grep -v "\${" | cut -d'=' -f2- | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
            
            # 如果 .env 中有有效值（不是占位符、不是空、不包含 ${}），使用它
            if [ -n "$AWS_S3_ACCESS_FROM_ENV" ] && [ "$AWS_S3_ACCESS_FROM_ENV" != "PLACEHOLDER_ACCESS_KEY" ] && [ "$AWS_S3_ACCESS_FROM_ENV" != "${AWS_S3_ACCESS}" ] && ! echo "$AWS_S3_ACCESS_FROM_ENV" | grep -q '\${'; then
                export AWS_S3_ACCESS="$AWS_S3_ACCESS_FROM_ENV"
                export AWS_S3_SECRET="$AWS_S3_SECRET_FROM_ENV"
                echo "✅ AWS S3 凭证已从 .env 文件加载"
            else
                echo "⚠️  .env 文件中的 AWS_S3 配置无效或缺失，需要重新配置"
                # 删除无效的 AWS_S3 配置
                grep -v "^AWS_S3" .env > .env.tmp && mv .env.tmp .env
            fi
            
            # 加载其他环境变量（除了 AWS_S3，避免循环引用）
            while IFS='=' read -r key value; do
                # 跳过注释、空行和 AWS_S3 相关配置
                if [[ "$key" =~ ^[[:space:]]*# ]] || [ -z "$key" ] || [[ "$key" =~ ^AWS_S3 ]]; then
                    continue
                fi
                # 移除可能的引号
                value=$(echo "$value" | sed "s/^['\"]//;s/['\"]$//")
                export "$key=$value"
            done < .env
        else
            echo "⚠️  .env 文件不存在，将创建新文件"
            touch .env
        fi
        
        # 配置 AWS S3 凭证（如果未设置或使用占位符）
        if [ -z "${AWS_S3_ACCESS:-}" ] || [ "${AWS_S3_ACCESS}" = "PLACEHOLDER_ACCESS_KEY" ] || [ "${AWS_S3_ACCESS}" = "${AWS_S3_ACCESS}" ]; then
            echo ""
            echo "⚠️  AWS S3 凭证未配置或使用占位符值"
            echo "   需要配置 S3 凭证以支持 RCTI 文件上传功能"
            echo ""
            read -p "请输入 AWS S3 Access Key ID (或按 Enter 跳过): " AWS_S3_ACCESS_INPUT
            if [ -n "$AWS_S3_ACCESS_INPUT" ]; then
                export AWS_S3_ACCESS="$AWS_S3_ACCESS_INPUT"
                read -sp "请输入 AWS S3 Secret Access Key: " AWS_S3_SECRET_INPUT
                echo ""
                if [ -n "$AWS_S3_SECRET_INPUT" ]; then
                    export AWS_S3_SECRET="$AWS_S3_SECRET_INPUT"
                    echo "✅ AWS S3 凭证已设置"
                    
                    # 保存到 .env 文件（如果存在）
                    if [ -f .env ]; then
                        # 删除旧的 AWS_S3 配置
                        grep -v "^AWS_S3" .env > .env.tmp && mv .env.tmp .env
                        # 验证值不包含占位符或变量引用
                        if echo "$AWS_S3_ACCESS" | grep -q '\${' || echo "$AWS_S3_SECRET" | grep -q '\${'; then
                            echo "❌ 错误: S3 凭证值包含占位符，无法保存"
                            export AWS_S3_ACCESS="PLACEHOLDER_ACCESS_KEY"
                            export AWS_S3_SECRET="PLACEHOLDER_SECRET_KEY"
                        else
                            # 添加新的配置（确保值是纯值，不包含变量引用）
                            echo "AWS_S3_ACCESS=$AWS_S3_ACCESS" >> .env
                            echo "AWS_S3_SECRET=$AWS_S3_SECRET" >> .env
                            echo "✅ AWS S3 凭证已保存到 .env 文件"
                        fi
                    fi
                else
                    echo "⚠️  未输入 Secret Key，将使用占位符值"
                    export AWS_S3_ACCESS="PLACEHOLDER_ACCESS_KEY"
                    export AWS_S3_SECRET="PLACEHOLDER_SECRET_KEY"
                fi
            else
                echo "⚠️  跳过 S3 配置，将使用占位符值（RCTI 文件上传功能将不可用）"
                export AWS_S3_ACCESS="PLACEHOLDER_ACCESS_KEY"
                export AWS_S3_SECRET="PLACEHOLDER_SECRET_KEY"
            fi
        else
            echo "✅ AWS S3 凭证已从环境变量加载"
        fi
        
        # 更新后端代码
        BACKEND_DIR="${BACKEND_DIR:-HarbourX-Backend}"
        BACKEND_PATH="$PROJECT_ROOT/$BACKEND_DIR"
        echo "更新后端代码（从 GitHub 拉取）: $BACKEND_PATH"
        
        if [ -d "$BACKEND_PATH/.git" ]; then
            echo "  后端仓库已存在，拉取最新代码..."
            cd "$BACKEND_PATH"
            CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
            echo "  当前分支: $CURRENT_BRANCH"
            
            # 配置 git 使用 token
            if [ -n "$GITHUB_TOKEN" ]; then
                CURRENT_REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
                if echo "$CURRENT_REMOTE_URL" | grep -qiE "github\.com[:/]"; then
                    REPO_PATH=$(echo "$CURRENT_REMOTE_URL" | sed -E "s|.*github\.com[:/]||" | sed "s|^[^/]*@||" | sed "s|^https://||" | sed "s|^github\.com/||" | sed "s|/$||")
                    if [ -n "$REPO_PATH" ] && echo "$REPO_PATH" | grep -qE "^[^/]+/[^/]+"; then
                        NEW_REMOTE_URL="https://${GITHUB_TOKEN}@github.com/$REPO_PATH"
                        git remote set-url origin "$NEW_REMOTE_URL" || exit 1
                    fi
                elif echo "$CURRENT_REMOTE_URL" | grep -q "^git@github.com:"; then
                    REPO_PATH=$(echo "$CURRENT_REMOTE_URL" | sed "s|git@github.com:||")
                    NEW_REMOTE_URL="https://${GITHUB_TOKEN}@github.com/$REPO_PATH"
                    git remote set-url origin "$NEW_REMOTE_URL" || exit 1
                fi
            fi
            
            # 拉取最新代码
            echo "  从 GitHub 拉取最新代码..."
            if ! git fetch origin main; then
                echo "  ❌ git fetch 失败，终止部署"
                exit 1
            fi
            if ! git reset --hard origin/main; then
                echo "  ❌ git reset 失败，终止部署"
                exit 1
            fi
            if ! git checkout main; then
                echo "  ❌ git checkout 失败，终止部署"
                exit 1
            fi
            
            LATEST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "unknown")
            echo "  ✅ 代码拉取成功"
            echo "  最新 commit: $LATEST_COMMIT"
            cd /opt/harbourx
        elif [ ! -d "$BACKEND_PATH" ]; then
            echo "  从 GitHub 克隆后端仓库..."
            cd "$PROJECT_ROOT"
            if [ -n "$GITHUB_TOKEN" ]; then
                if ! git clone https://${GITHUB_TOKEN}@github.com/HarbourX-Team/HarbourX-Backend.git "$BACKEND_DIR"; then
                    echo "  ❌ 克隆失败，终止部署"
                    exit 1
                fi
            else
                if ! git clone https://github.com/HarbourX-Team/HarbourX-Backend.git "$BACKEND_DIR"; then
                    echo "  ❌ 克隆失败，终止部署"
                    exit 1
                fi
            fi
            cd /opt/harbourx
        fi
        
        # 确保在部署目录
        cd /opt/harbourx
        
        # 在部署开始前，清理 .env 文件中的无效配置
        if [ -f .env ]; then
            echo "清理 .env 文件中的无效配置（部署前检查）..."
            # 备份 .env 文件
            cp .env .env.backup.$(date +%s) 2>/dev/null || true
            # 删除所有包含 ${} 占位符的 AWS_S3 配置行
            grep -v "^AWS_S3.*\${" .env > .env.tmp 2>/dev/null || cat .env > .env.tmp
            mv .env.tmp .env
            # 删除所有包含循环引用的 AWS_S3 配置行
            grep -v "^AWS_S3.*AWS_S3" .env > .env.tmp 2>/dev/null || cat .env > .env.tmp
            mv .env.tmp .env
            echo "✅ .env 文件已清理"
        fi
        
        # 确保 Docker 可以访问构建上下文
        # 修复可能的权限问题
        sudo chown -R $(whoami):$(whoami) . 2>/dev/null || true
        chmod -R u+rw . 2>/dev/null || true
        
        # 确保父目录权限正确（PROJECT_ROOT）
        if [ -d "$PROJECT_ROOT" ]; then
            sudo chown -R $(whoami):$(whoami) "$PROJECT_ROOT" 2>/dev/null || true
            chmod -R u+rw "$PROJECT_ROOT" 2>/dev/null || true
        fi
        
        # 先启动 postgres，等待它完全启动
        echo "启动 PostgreSQL 数据库..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml up -d postgres
        
        # 等待 postgres 完全启动
        echo "等待 PostgreSQL 启动..."
        for i in {1..30}; do
            if docker exec harbourx-postgres pg_isready -U harbourx > /dev/null 2>&1; then
                echo "  ✅ PostgreSQL 已就绪"
                break
            fi
            if [ $i -eq 30 ]; then
                echo "  ⚠️  警告: PostgreSQL 启动超时，但继续执行..."
            fi
            sleep 1
        done
        
        # 删除并重新创建数据库
        echo "删除并重新创建数据库..."
        docker exec harbourx-postgres psql -U harbourx -c "DROP DATABASE IF EXISTS harbourx;" 2>/dev/null || true
        docker exec harbourx-postgres psql -U harbourx -c "CREATE DATABASE harbourx;" 2>/dev/null || true
        echo "  ✅ 数据库已重新创建"
        
        # 构建并启动后端服务
        echo "构建后端服务镜像..."
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
        $DOCKER_COMPOSE_CMD -f docker-compose.yml build --no-cache backend
        
        echo "启动后端服务..."
        
        # 在启动前，强制清理可能存在的容器（防止名称冲突）
        echo "清理可能存在的后端容器..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml rm -f backend 2>/dev/null || true
        docker rm -f harbourx-backend 2>/dev/null || true
        # 确保容器完全移除
        sleep 1
        
        # 确保环境变量被正确传递到 Docker Compose
        # Docker Compose 会自动读取 .env 文件，但为了确保正确，显式导出
        # 在启动前，再次验证和清理 .env 文件
        if [ -f .env ]; then
            echo "验证 .env 文件中的 AWS_S3 配置..."
            # 删除所有包含 ${} 占位符的 AWS_S3 配置行
            grep -v "^AWS_S3.*\${" .env > .env.tmp 2>/dev/null || cat .env > .env.tmp
            mv .env.tmp .env
            # 从 .env 文件读取 AWS_S3 配置并导出（排除包含 ${} 的行）
            AWS_S3_ACCESS_VAL=$(grep "^AWS_S3_ACCESS=" .env | grep -v "^#" | grep -v "\${" | cut -d'=' -f2- | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
            AWS_S3_SECRET_VAL=$(grep "^AWS_S3_SECRET=" .env | grep -v "^#" | grep -v "\${" | cut -d'=' -f2- | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
            # 验证值不包含占位符
            if [ -n "$AWS_S3_ACCESS_VAL" ] && [ "$AWS_S3_ACCESS_VAL" != "PLACEHOLDER_ACCESS_KEY" ] && ! echo "$AWS_S3_ACCESS_VAL" | grep -q '\${'; then
                export AWS_S3_ACCESS="$AWS_S3_ACCESS_VAL"
                export AWS_S3_SECRET="$AWS_S3_SECRET_VAL"
                echo "✅ AWS S3 凭证已验证并导出"
            else
                echo "⚠️  .env 文件中的 AWS_S3 配置无效，使用占位符值"
                export AWS_S3_ACCESS="PLACEHOLDER_ACCESS_KEY"
                export AWS_S3_SECRET="PLACEHOLDER_SECRET_KEY"
            fi
        fi
        $DOCKER_COMPOSE_CMD -f docker-compose.yml up -d backend
        
        echo "等待服务启动..."
        sleep 10
        
        echo "检查服务状态..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml ps backend postgres
        
        echo "查看后端日志（最近 20 行）..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml logs --tail=20 backend
EOF
    
    echo_info "✅ 后端部署完成！"
    echo ""
    echo "📋 访问地址："
    echo "  - 后端 API: http://$EC2_HOST:8080"
    echo "  - Swagger: http://$EC2_HOST:8080/swagger-ui.html"
    echo ""
    echo "💡 部署方式说明："
    echo "  ✅ 手动部署：./harbourx.sh deploy backend（当前使用）"
    echo "  ✅ CI/CD 自动部署：Push 代码到 main 分支，触发 .github/workflows/cd.yml"
}

# 手动部署前端 - 独立于 CI/CD
deploy_deploy_frontend() {
    echo_info "手动部署前端到 EC2 实例: $EC2_HOST"
    echo_info "注意：这是手动部署方式，独立于 GitHub Actions CI/CD"
    echo ""
    read -p "确认继续部署前端？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "已取消部署。"
        return 0
    fi
    
    # ============================================
    # 1. 优先检测 GitHub 登录（必需）
    # ============================================
    echo_info "步骤 1/5: 检测 GitHub 登录状态..."
    
    GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    GITHUB_AUTH_METHOD=""
    
    # 方法 1: 检查环境变量
    if [ -n "$GITHUB_TOKEN" ]; then
        echo_info "  检测到 GITHUB_TOKEN 环境变量"
        GITHUB_AUTH_METHOD="env"
    else
        # 方法 2: 尝试从 gh CLI 获取 token
        if command -v gh &> /dev/null; then
            echo_info "  尝试使用 GitHub CLI (gh) 获取 token..."
            GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
            if [ -n "$GITHUB_TOKEN" ]; then
                echo_info "  ✅ 从 gh CLI 获取到 token"
                GITHUB_AUTH_METHOD="gh_cli"
            else
                echo_warn "  ⚠️  gh CLI 未登录或 token 无效"
            fi
        else
            echo_warn "  ⚠️  GitHub CLI (gh) 未安装"
        fi
    fi
    
    # 验证 GitHub token 是否有效
    if [ -n "$GITHUB_TOKEN" ]; then
        echo_info "  验证 GitHub token 有效性..."
        if command -v curl &> /dev/null; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                https://api.github.com/user 2>/dev/null || echo "000")
            
            if [ "$HTTP_CODE" = "200" ]; then
                GITHUB_USER=$(curl -s \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    https://api.github.com/user 2>/dev/null | grep -o '"login":"[^"]*' | cut -d'"' -f4 || echo "unknown")
                echo_info "  ✅ GitHub token 有效 (用户: $GITHUB_USER)"
                
                # 检查前端仓库访问权限
                REPO_CHECK_FRONTEND=$(curl -s -o /dev/null -w "%{http_code}" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    https://api.github.com/repos/HarbourX-Team/HarbourX-Frontend 2>/dev/null || echo "000")
                
                if [ "$REPO_CHECK_FRONTEND" = "200" ]; then
                    echo_info "  ✅ 有权限访问前端仓库"
                else
                    echo_warn "  ⚠️  无法访问前端仓库 (HTTP $REPO_CHECK_FRONTEND)"
                fi
            else
                echo_error "  ❌ GitHub token 无效或已过期 (HTTP $HTTP_CODE)"
                return 1
            fi
        fi
    else
        echo_error "❌ 未检测到 GitHub 认证信息！"
        return 1
    fi
    
    echo_info "✅ GitHub 登录验证通过"
    echo ""
    
    # ============================================
    # 2. 检查 SSH 密钥
    # ============================================
    echo_info "步骤 2/5: 检查 SSH 密钥..."
    if [ ! -f "$SSH_KEY" ]; then
        echo_error "SSH 密钥文件不存在: $SSH_KEY"
        return 1
    fi
    chmod 400 "$SSH_KEY" 2>/dev/null || true
    echo_info "✅ SSH 密钥检查通过"
    echo ""
    
    # ============================================
    # 3. 检查 SSH 连接
    # ============================================
    echo_info "步骤 3/5: 检查 SSH 连接..."
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "echo '连接成功'" > /dev/null 2>&1; then
        echo_error "无法连接到 EC2 实例"
        return 1
    fi
    echo_info "✅ SSH 连接成功"
    echo ""
    
    # ============================================
    # 4. 上传 harbourX 配置（如果需要）
    # ============================================
    echo_info "步骤 4/5: 上传 harbourX 配置..."
    TAR_FILE="/tmp/harbourx-$(date +%s).tar.gz"
    tar -czf "$TAR_FILE" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='target' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.env' \
        --exclude='containerd' \
        --exclude='*.log' \
        --exclude='.DS_Store' \
        --exclude='*.tar.gz' \
        . 2>/dev/null
    
    scp -i "$SSH_KEY" "$TAR_FILE" "${EC2_USER}@${EC2_HOST}:~/"
    rm -f "$TAR_FILE"
    echo_info "✅ 配置已上传"
    echo ""
    
    # ============================================
    # 5. 在 EC2 上部署前端服务
    # ============================================
    echo_info "步骤 5/5: 在 EC2 上部署前端服务..."
    
    TAR_FILE_BASENAME=$(basename "$TAR_FILE")
    ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "GITHUB_TOKEN='$GITHUB_TOKEN' TAR_FILE_BASENAME='$TAR_FILE_BASENAME' bash -s" << 'EOF'
        set -e
        cd ~
        sudo mkdir -p /opt/harbourx
        sudo tar -xzf "$TAR_FILE_BASENAME" -C /opt/harbourx 2>/dev/null || true
        sudo chown -R $USER:$USER /opt/harbourx
        rm -f "$TAR_FILE_BASENAME"
        
        cd /opt/harbourx
        
        # 检测实际的 docker 配置目录名
        # 当前目录应该就是包含 dockerfiles 的目录
        if [ -d "dockerfiles" ]; then
            # 当前目录就是 docker 配置目录，使用当前目录名
            CURRENT_PWD=$(pwd)
            DOCKER_DIR_NAME=$(basename "$CURRENT_PWD")
            export DOCKER_DIR="$DOCKER_DIR_NAME"
        elif [ -d "harbourX" ] && [ -d "harbourX/dockerfiles" ]; then
            export DOCKER_DIR="harbourX"
        elif [ -d "harbourx" ] && [ -d "harbourx/dockerfiles" ]; then
            export DOCKER_DIR="harbourx"
        else
            # 查找包含 dockerfiles 的目录
            DOCKER_DIR_FOUND=$(find . -maxdepth 2 -type d -name "dockerfiles" -exec dirname {} \; | head -1 | xargs basename 2>/dev/null)
            if [ -n "$DOCKER_DIR_FOUND" ] && [ "$DOCKER_DIR_FOUND" != "." ]; then
                export DOCKER_DIR="$DOCKER_DIR_FOUND"
            else
                export DOCKER_DIR="harbourX"
            fi
        fi
        echo "当前目录: $(pwd)"
        echo "使用 DOCKER_DIR: $DOCKER_DIR"
        echo "检查 dockerfiles 目录: $(ls -la dockerfiles 2>/dev/null | head -3 || echo 'dockerfiles 不存在')"
        
        # 检测 docker compose 命令
        if command -v docker-compose &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker-compose"
        else
            DOCKER_COMPOSE_CMD="docker compose"
        fi
        
        # 停止前端服务
        echo "停止前端服务..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml stop frontend 2>/dev/null || true
        # 清理前端容器（包括可能存在的遗留容器）
        $DOCKER_COMPOSE_CMD -f docker-compose.yml rm -f frontend 2>/dev/null || true
        docker rm -f harbourx-frontend 2>/dev/null || true
        
        # 注意：frontend 依赖于 backend 和 ai-module（根据 docker-compose.yml 的 depends_on）
        # 但使用 --no-deps 选项后，不会启动依赖服务，所以不会影响其他容器
        # 如果 backend 或 ai-module 容器已存在但停止，不会导致冲突（因为不会尝试启动它们）
        echo "✅ 前端容器已清理，依赖服务（backend、ai-module）不会受影响"
        sleep 1
        
        # 设置环境变量
        export PROJECT_ROOT=".."
        export DOCKER_DIR="$DOCKER_DIR"
        
        # 更新前端代码
        FRONTEND_DIR="${FRONTEND_DIR:-HarbourX-Frontend}"
        FRONTEND_PATH="$PROJECT_ROOT/$FRONTEND_DIR"
        echo "更新前端代码（从 GitHub 拉取）: $FRONTEND_PATH"
        
        if [ -d "$FRONTEND_PATH/.git" ]; then
            echo "  前端仓库已存在，拉取最新代码..."
            cd "$FRONTEND_PATH"
            CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
            echo "  当前分支: $CURRENT_BRANCH"
            
            # 配置 git 使用 token
            if [ -n "$GITHUB_TOKEN" ]; then
                CURRENT_REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
                if echo "$CURRENT_REMOTE_URL" | grep -qiE "github\.com[:/]"; then
                    REPO_PATH=$(echo "$CURRENT_REMOTE_URL" | sed -E "s|.*github\.com[:/]||" | sed "s|^[^/]*@||" | sed "s|^https://||" | sed "s|^github\.com/||" | sed "s|/$||")
                    if [ -n "$REPO_PATH" ] && echo "$REPO_PATH" | grep -qE "^[^/]+/[^/]+"; then
                        NEW_REMOTE_URL="https://${GITHUB_TOKEN}@github.com/$REPO_PATH"
                        git remote set-url origin "$NEW_REMOTE_URL" || exit 1
                    fi
                elif echo "$CURRENT_REMOTE_URL" | grep -q "^git@github.com:"; then
                    REPO_PATH=$(echo "$CURRENT_REMOTE_URL" | sed "s|git@github.com:||")
                    NEW_REMOTE_URL="https://${GITHUB_TOKEN}@github.com/$REPO_PATH"
                    git remote set-url origin "$NEW_REMOTE_URL" || exit 1
                fi
            fi
            
            # 拉取最新代码
            echo "  从 GitHub 拉取最新代码..."
            if ! git fetch origin main; then
                echo "  ❌ git fetch 失败，终止部署"
                exit 1
            fi
            if ! git reset --hard origin/main; then
                echo "  ❌ git reset 失败，终止部署"
                exit 1
            fi
            if ! git checkout main; then
                echo "  ❌ git checkout 失败，终止部署"
                exit 1
            fi
            
            LATEST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "unknown")
            echo "  ✅ 代码拉取成功"
            echo "  最新 commit: $LATEST_COMMIT"
            cd /opt/harbourx
        elif [ ! -d "$FRONTEND_PATH" ]; then
            echo "  从 GitHub 克隆前端仓库..."
            cd "$PROJECT_ROOT"
            if [ -n "$GITHUB_TOKEN" ]; then
                if ! git clone https://${GITHUB_TOKEN}@github.com/HarbourX-Team/HarbourX-Frontend.git "$FRONTEND_DIR"; then
                    echo "  ❌ 克隆失败，终止部署"
                    exit 1
                fi
            else
                if ! git clone https://github.com/HarbourX-Team/HarbourX-Frontend.git "$FRONTEND_DIR"; then
                    echo "  ❌ 克隆失败，终止部署"
                    exit 1
                fi
            fi
            cd /opt/harbourx
        fi
        
        # 确保在部署目录
        cd /opt/harbourx
        
        # 确保 Docker 可以访问构建上下文
        # 修复可能的权限问题
        sudo chown -R $(whoami):$(whoami) . 2>/dev/null || true
        chmod -R u+rw . 2>/dev/null || true
        
        # 确保父目录权限正确（PROJECT_ROOT）
        if [ -d "$PROJECT_ROOT" ]; then
            sudo chown -R $(whoami):$(whoami) "$PROJECT_ROOT" 2>/dev/null || true
            chmod -R u+rw "$PROJECT_ROOT" 2>/dev/null || true
        fi
        
        # 清理旧的 frontend 镜像
        echo "清理旧的 frontend 镜像..."
        docker rmi harbourx-frontend 2>/dev/null || true
        docker images | grep frontend | awk '{print \$3}' | xargs -r docker rmi -f 2>/dev/null || true
        
        # 构建并启动前端服务
        echo "构建前端服务镜像..."
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
        $DOCKER_COMPOSE_CMD -f docker-compose.yml build --no-cache frontend
        
        echo "启动前端服务..."
        # 使用 --no-deps 选项，避免启动依赖服务（backend、ai-module）
        # 因为 deploy frontend 只应该部署前端，不应该启动后端
        $DOCKER_COMPOSE_CMD -f docker-compose.yml up -d --no-deps frontend
        
        echo "等待服务启动..."
        sleep 10
        
        echo "检查服务状态..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml ps frontend
        
        echo "查看前端日志（最近 20 行）..."
        $DOCKER_COMPOSE_CMD -f docker-compose.yml logs --tail=20 frontend
EOF
    
    echo_info "✅ 前端部署完成！"
    echo ""
    echo "📋 访问地址："
    echo "  - 前端: http://$EC2_HOST"
    echo ""
    echo "💡 部署方式说明："
    echo "  ✅ 手动部署：./harbourx.sh deploy frontend（当前使用）"
    echo "  ✅ CI/CD 自动部署：Push 代码到 main 分支，触发 .github/workflows/CD.yml"
}

deploy_ssh() {
    echo_info "SSH 连接到 EC2 实例: $EC2_HOST"
    echo ""
    echo "登录后可以运行以下命令："
    echo "  docker ps -a          # 查看所有容器"
    echo "  docker ps             # 查看运行中的容器"
    echo "  docker logs <容器名>  # 查看容器日志"
    echo "  docker stats          # 查看资源使用"
    echo "  cd $DEPLOY_DIR        # 进入部署目录"
    echo ""
    echo "按 Ctrl+D 或输入 exit 退出"
    echo ""
    
    ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}"
}

deploy_ip() {
    local instance_id="${1:-i-0834ba4a42c0d9bd8}"
    local region="${2:-ap-southeast-2}"
    
    if ! command -v aws &> /dev/null; then
        echo_error "AWS CLI 未安装"
        echo ""
        echo "请手动从 AWS Console 获取公共 IP："
        echo "  1. 登录 AWS Console → EC2 → Instances"
        echo "  2. 找到实例 $instance_id"
        echo "  3. 查看 'Public IPv4 address'"
        return 1
    fi
    
    echo_info "获取 EC2 实例信息..."
    if ! aws sts get-caller-identity &> /dev/null; then
        echo_error "AWS CLI 未配置或没有权限"
        echo "请运行: aws configure"
        return 1
    fi
    
    RESULT=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --output json 2>&1)
    
    if [ $? -ne 0 ]; then
        echo_error "无法查询实例信息"
        echo "错误: $RESULT"
        return 1
    fi
    
    PUBLIC_IP=$(echo "$RESULT" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "None"' 2>/dev/null || echo "None")
    PRIVATE_IP=$(echo "$RESULT" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress // "None"' 2>/dev/null || echo "None")
    STATE=$(echo "$RESULT" | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"' 2>/dev/null || echo "unknown")
    
    echo ""
    echo "实例状态: $STATE"
    echo "私有 IP: $PRIVATE_IP"
    
    if [ "$PUBLIC_IP" != "None" ] && [ -n "$PUBLIC_IP" ]; then
        echo_info "公共 IP: $PUBLIC_IP"
        echo ""
        echo "使用以下命令设置并部署："
        echo "  export EC2_HOST=$PUBLIC_IP"
        echo "  ./harbourx.sh deploy deploy"
    else
        echo_warn "实例没有公共 IP 地址"
        echo ""
        echo "可能的原因："
        echo "  1. 实例没有分配公共 IP"
        echo "  2. 实例未运行（当前状态: $STATE）"
    fi
}

deploy_setup_git() {
    echo_warn "⚠️  此命令已废弃！"
    echo_warn "Git 仓库设置现在通过 GitHub Actions CI/CD 自动处理。"
    echo_warn ""
    echo_warn "CI/CD 会自动："
    echo_warn "  - 拉取最新代码"
    echo_warn "  - 构建和部署服务"
    echo_warn "  - 管理代码版本"
    echo_warn ""
    echo ""
    read -p "是否继续执行废弃的设置命令？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "已取消。请使用 GitHub Actions CI/CD 进行部署。"
        return 0
    fi
    
    echo_info "在 EC2 上设置 Git 仓库..."
    
    if [ ! -f "$SSH_KEY" ]; then
        echo_error "SSH 密钥文件不存在: $SSH_KEY"
        return 1
    fi
    
    GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo '')}"
    
    ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" << EOF
        set -e
        # 安装 Git
        sudo yum install git -y 2>/dev/null || sudo apt-get install git -y 2>/dev/null || true
        
        # Frontend 仓库
        echo "设置 HarbourX-Frontend..."
        cd /opt
        if [ -d "HarbourX-Frontend" ]; then
            echo "  仓库已存在，跳过克隆"
        else
            echo "  克隆 Frontend 仓库..."
            if [ -n "$GITHUB_TOKEN" ]; then
                sudo git clone https://${GITHUB_TOKEN}@github.com/HarbourX-Team/HarbourX-Frontend.git
            else
                sudo git clone https://github.com/HarbourX-Team/HarbourX-Frontend.git
            fi
            sudo chown -R ${EC2_USER}:${EC2_USER} HarbourX-Frontend
        fi
        
        # Backend 仓库
        echo "设置 HarbourX-Backend..."
        if [ -d "HarbourX-Backend" ]; then
            echo "  仓库已存在，跳过克隆"
        else
            echo "  克隆 Backend 仓库..."
            if [ -n "$GITHUB_TOKEN" ]; then
                sudo git clone https://${GITHUB_TOKEN}@github.com/HarbourX-Team/HarbourX-Backend.git
            else
                sudo git clone https://github.com/HarbourX-Team/HarbourX-Backend.git
            fi
            sudo chown -R ${EC2_USER}:${EC2_USER} HarbourX-Backend
        fi
        
        # AI-Module 仓库
        echo "设置 AI-Module..."
        if [ -d "AI-Module" ]; then
            echo "  仓库已存在，跳过克隆"
        else
            echo "  克隆 AI-Module 仓库..."
            if [ -n "$GITHUB_TOKEN" ]; then
                sudo git clone https://${GITHUB_TOKEN}@github.com/HaimoneyTeam/AI-Module.git
            else
                sudo git clone https://github.com/HaimoneyTeam/AI-Module.git
            fi
            sudo chown -R ${EC2_USER}:${EC2_USER} AI-Module
        fi
EOF
    
    echo_info "Git 仓库设置完成！"
}

deploy_create_broker() {
    BASE_URL="http://${EC2_HOST}:8080"
    
    echo_info "开始创建 Broker..."
    
    # 登录获取 JWT Token
    echo ""
    echo_info "步骤 1: 登录获取 JWT Token..."
    LOGIN_RESPONSE=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{
            "identityType": "EMAIL",
            "identity": "systemadmin@harbourx.com.au",
            "password": "password"
        }')
    
    TOKEN=$(echo $LOGIN_RESPONSE | grep -o '"jwt":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$TOKEN" ]; then
        echo_error "登录失败，请检查账号密码"
        echo "响应: $LOGIN_RESPONSE"
        return 1
    fi
    
    echo_info "登录成功，Token: ${TOKEN:0:20}..."
    
    # 创建用户
    echo ""
    echo_info "步骤 2: 创建用户..."
    USER_RESPONSE=$(curl -s -X POST "${BASE_URL}/api/admin/users" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        -d '{
            "displayName": "John Doe",
            "password": "password",
            "status": "ACTIVE",
            "userIdentityType": "EMAIL",
            "userIdentityValue": "alice@example.com",
            "verified": true,
            "firstName": "John",
            "lastName": "Doe",
            "userRole": {
                "roleId": 3,
                "companyId": 2
            }
        }')
    
    USER_ID=$(echo $USER_RESPONSE | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [ -z "$USER_ID" ]; then
        if echo "$USER_RESPONSE" | grep -q "already exists"; then
            echo_warn "用户已存在，尝试获取用户信息..."
            USERS_RESPONSE=$(curl -s -X GET "${BASE_URL}/api/admin/users" \
                -H "Authorization: Bearer ${TOKEN}")
            USER_ID=$(echo $USERS_RESPONSE | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            if [ -z "$USER_ID" ]; then
                echo_error "无法获取用户 ID"
                return 1
            fi
            echo_info "找到已存在的用户，User ID: $USER_ID"
        else
            echo_error "创建用户失败"
            echo "响应: $USER_RESPONSE"
            return 1
        fi
    else
        echo_info "用户创建成功，User ID: $USER_ID"
    fi
    
    # 创建或更新 Broker
    echo ""
    echo_info "步骤 3: 创建或更新 Broker 记录..."
    BROKER_RESPONSE=$(curl -s -X POST "${BASE_URL}/api/broker" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        -d '{
            "name": "Alice Broker",
            "email": "alice@example.com",
            "type": "DIRECT_PAYMENT",
            "crn": "CRN123456",
            "brokerGroupId": 2
        }')
    
    BROKER_ID=$(echo $BROKER_RESPONSE | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [ -z "$BROKER_ID" ]; then
        if echo "$BROKER_RESPONSE" | grep -q "already exists\|Failed to execute\|duplicate"; then
            echo_warn "Broker 记录已存在，尝试更新..."
            ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "cd $DEPLOY_DIR && docker-compose exec -T postgres psql -U harbourx -d harbourx -c \"UPDATE brokers SET user_id = (SELECT u.id FROM users u JOIN user_identities ui ON u.id = ui.user_id WHERE ui.identity = 'alice@example.com' AND ui.type = 'EMAIL' LIMIT 1) WHERE email = 'alice@example.com';\" > /dev/null 2>&1" || true
            
            BROKER_ID=$(ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "cd $DEPLOY_DIR && docker-compose exec -T postgres psql -U harbourx -d harbourx -t -c \"SELECT id FROM brokers WHERE email = 'alice@example.com' LIMIT 1;\" | tr -d ' '" || echo "")
            
            if [ -n "$BROKER_ID" ] && [ "$BROKER_ID" != "" ]; then
                echo_info "Broker 记录已更新，Broker ID: $BROKER_ID"
            else
                echo_error "更新 Broker 记录失败"
                return 1
            fi
        else
            echo_error "创建 Broker 记录失败"
            echo "响应: $BROKER_RESPONSE"
            return 1
        fi
    else
        echo_info "Broker 记录创建成功，Broker ID: $BROKER_ID"
    fi
    
    echo ""
    echo_info "完成！Broker 已创建并激活"
    echo "   - User ID: $USER_ID"
    echo "   - Broker ID: $BROKER_ID"
    echo "   - Email: alice@example.com"
    echo "   - 登录密码: password"
}

# 复制 .env 文件从 AI-Module 目录到 Docker 容器
docker_copy_env() {
    echo_info "复制 .env 文件从 AI-Module 目录到 Docker 容器..."
    
    # 获取项目路径
    PROJECT_ROOT="${PROJECT_ROOT:-..}"
    AI_MODULE_DIR="${AI_MODULE_DIR:-AI-Module}"
    AI_MODULE_PATH="$PROJECT_ROOT/$AI_MODULE_DIR"
    ENV_FILE="$AI_MODULE_PATH/.env"
    
    # 检查 AI-Module 目录是否存在
    if [ ! -d "$AI_MODULE_PATH" ]; then
        echo_error "AI-Module 目录不存在: $AI_MODULE_PATH"
        echo_error "请检查 PROJECT_ROOT 和 AI_MODULE_DIR 环境变量"
        return 1
    fi
    
    # 检查 .env 文件是否存在
    if [ ! -f "$ENV_FILE" ]; then
        echo_error ".env 文件不存在于 AI-Module 目录: $ENV_FILE"
        echo_error "请确保 .env 文件存在于 $AI_MODULE_PATH/.env"
        return 1
    fi
    
    # 检查 AI-Module 容器是否运行
    if ! docker ps --format "{{.Names}}" | grep -q "^harbourx-ai-module$"; then
        echo_error "AI-Module 容器未运行"
        echo_error "请先启动容器: ./harbourx.sh docker start"
        return 1
    fi
    
    # 复制 .env 文件到容器内的 /app/.env
    echo_info "从 $ENV_FILE 复制到容器 harbourx-ai-module:/app/.env"
    docker cp "$ENV_FILE" harbourx-ai-module:/app/.env
    
    if [ $? -eq 0 ]; then
        # 在容器内设置适当的权限
        docker exec harbourx-ai-module chmod 600 /app/.env 2>/dev/null || true
        echo_info "✅ .env 文件已复制到 AI-Module 容器: /app/.env"
        
        echo_warn "注意: 环境变量已通过 docker-compose env_file 自动加载"
        echo_info "如果容器需要重新加载环境变量，请重启容器："
        echo "  ./harbourx.sh docker restart ai-module"
        echo ""
        read -p "是否现在重启 AI-Module 容器以应用更改？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo_info "重启 AI-Module 容器..."
            docker restart harbourx-ai-module
            echo_info "✅ AI-Module 容器已重启"
        fi
    else
        echo_error "❌ 复制 .env 文件到容器失败"
        return 1
    fi
}

# 配置命令
config_env() {
    echo_info "当前配置："
    echo ""
    echo "  EC2_HOST:      ${EC2_HOST}"
    echo "  EC2_USER:      ${EC2_USER}"
    echo "  SSH_KEY:       ${SSH_KEY}"
    echo "  DEPLOY_DIR:    ${DEPLOY_DIR}"
    echo "  PROJECT_ROOT:  ${PROJECT_ROOT:-..}"
    echo "  BACKEND_DIR:   ${BACKEND_DIR:-HarbourX-Backend}"
    echo "  FRONTEND_DIR:  ${FRONTEND_DIR:-HarbourX-Frontend}"
    echo "  AI_MODULE_DIR: ${AI_MODULE_DIR:-AI-Module}"
    echo ""
  echo "要修改配置，可以："
  echo "  1. 设置环境变量: export EC2_HOST=your-ip"
  echo "  2. 或创建 .env 文件（参考 env.example）"
  echo ""
  echo "注意："
  echo "  - 本地开发环境变量请参考 env.example 文件"
  echo "  - 生产环境部署通过 GitHub Actions CI/CD 自动完成"
  echo "  - 生产环境配置存储在 EC2 实例的 /opt/harbourx/.env 文件中"
}

# 主函数
main() {
    local command="${1:-help}"
    local subcommand="${2:-}"
    local arg1="${3:-}"
    local arg2="${4:-}"
    
    case "$command" in
        docker)
            case "$subcommand" in
                start)
                    docker_start "$arg1"
                    ;;
                start:dev)
                    docker_start "dev"
                    ;;
                stop)
                    docker_stop
                    ;;
                stop:all)
                    docker_stop_all
                    ;;
                restart)
                    docker_restart "$arg1"
                    ;;
                logs)
                    docker_logs "$arg1" "$arg2"
                    ;;
                status)
                    docker_status
                    ;;
                clean)
                    docker_clean
                    ;;
                clean:all)
                    docker_clean_all
                    ;;
                copy-env)
                    docker_copy_env
                    ;;
                *)
                    echo_error "未知的 docker 子命令: $subcommand"
                    echo "使用 './harbourx.sh docker help' 查看帮助"
                    ;;
            esac
            ;;
        deploy)
            case "$subcommand" in
                local)
                    deploy_local "$arg1" "$arg2"
                    ;;
                backend)
                    deploy_deploy_backend
                    ;;
                frontend)
                    deploy_deploy_frontend
                    ;;
                deploy)
                    deploy_deploy
                    ;;
                ssh)
                    deploy_ssh
                    ;;
                ip)
                    deploy_ip "$arg1" "$arg2"
                    ;;
                setup-git)
                    deploy_setup_git
                    ;;
                create-broker)
                    deploy_create_broker
                    ;;
                *)
                    echo_error "未知的 deploy 子命令: $subcommand"
                    echo "使用 './harbourx.sh help' 查看帮助"
                    ;;
            esac
            ;;
        config)
            case "$subcommand" in
                env)
                    config_env
                    ;;
                *)
                    echo_error "未知的 config 子命令: $subcommand"
                    ;;
            esac
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"

