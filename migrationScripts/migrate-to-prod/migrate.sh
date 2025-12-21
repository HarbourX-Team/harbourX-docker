#!/bin/bash

# 生产环境完整迁移脚本
# 使用此脚本将数据从老系统迁移到生产 HarbourX 环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载配置
source "$SCRIPT_DIR/config.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 检查生产环境密码
if [ -z "$LOGIN_PASSWORD" ]; then
    echo_error "生产环境需要提供 LOGIN_PASSWORD"
    echo "请设置环境变量: export LOGIN_PASSWORD='your-password'"
    exit 1
fi

echo ""
echo_info "=========================================="
echo_info "  生产环境数据迁移"
echo_info "  目标: $API_BASE_URL"
echo_info "=========================================="
echo ""
echo_warn "⚠️  警告: 您正在迁移到生产环境！"
read -p "确认继续? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "已取消"
    exit 0
fi

# 步骤 1: 迁移 Broker Groups
echo_info "步骤 1: 迁移 Broker Groups..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./migrate-broker-groups.sh

if [ $? -ne 0 ]; then
    echo_error "Broker Groups 迁移失败"
    exit 1
fi

echo ""
echo_success "Broker Groups 迁移完成"
echo ""

# 步骤 2: 迁移 Brokers
echo_info "步骤 2: 迁移 Brokers..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./migrate-brokers.sh

if [ $? -ne 0 ]; then
    echo_error "Brokers 迁移失败"
    exit 1
fi

echo ""
echo_success "Brokers 迁移完成"
echo ""

# 步骤 3: 重新迁移失败的 Brokers（如果有）
echo_info "步骤 3: 重新迁移失败的 Brokers..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./migrate-failed-brokers.sh

echo ""

# 步骤 4: 修复 created_at 和 deleted_at 时间戳（迁移完成后自动运行）
echo_info "步骤 4: 修复 created_at 和 deleted_at 时间戳..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"

# 尝试使用 PROD_DB_* 变量（如果配置了）
if [ -n "$PROD_DB_PASS" ]; then
    echo_info "使用配置的生产数据库连接信息..."
    # 导出 PROD_DB_* 变量供 fix-cloud-created-at.sh 使用
    export PROD_DB_HOST="$PROD_DB_HOST"
    export PROD_DB_PORT="$PROD_DB_PORT"
    export PROD_DB_USER="$PROD_DB_USER"
    export PROD_DB_NAME="$PROD_DB_NAME"
    export PROD_DB_PASS="$PROD_DB_PASS"
    ./fix-cloud-created-at.sh
    
    if [ $? -ne 0 ]; then
        echo_warn "created_at 修复过程中出现警告（可能是没有 loans 数据，这是正常的）"
    fi
    
    echo ""
    echo_info "步骤 4.5: 验证 created_at 和 deleted_at 修复..."
    ./verify-created-at.sh prod
else
    echo_warn "未配置 PROD_DB_PASS，无法自动修复 created_at"
    echo_warn "注意: 如果无法直接访问生产数据库，created_at 修复将跳过"
    echo_warn "这不会影响迁移，但可能导致 MISSING_BROKER_GROUP 错误"
    echo_warn "建议: 配置 PROD_DB_* 环境变量以启用自动修复"
    echo ""
    echo_info "跳过 created_at 修复（需要直接数据库访问）"
    echo_info "如需修复，请设置 PROD_DB_* 环境变量并重新运行此步骤"
fi

echo ""
echo_success "所有迁移步骤完成！"
echo ""
