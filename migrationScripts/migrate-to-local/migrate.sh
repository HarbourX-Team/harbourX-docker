#!/bin/bash

# 本地环境完整迁移脚本
# 使用此脚本将数据从老系统迁移到本地 HarbourX 环境

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

echo ""
echo_info "=========================================="
echo_info "  本地环境数据迁移"
echo_info "  目标: $API_BASE_URL"
echo_info "=========================================="
echo ""

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

# 步骤 1.3: 映射验证和清理（已整合到 migrate-broker-groups.sh）
echo_info "步骤 1.3: Broker Group 映射验证..."
echo_warn "映射验证和清理已整合到 migrate-broker-groups.sh 中"

# 步骤 1.5: 验证并修复 Broker Groups 和 Aggregator 的关系
echo_info "步骤 1.5: 验证并修复 Broker Groups 和 Aggregator 的关系..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./verify-relationships.sh

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

# 步骤 2.5: 再次验证关系（确保所有关系正确）
echo_info "步骤 2.5: 再次验证关系..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./verify-relationships.sh

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
./fix-local-created-at.sh

if [ $? -ne 0 ]; then
    echo_warn "created_at 修复过程中出现警告（可能是没有 loans 数据，这是正常的）"
fi

echo ""

# 步骤 4.5: 验证 created_at 和 deleted_at 修复
echo_info "步骤 4.5: 验证 created_at 和 deleted_at 修复..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./verify-created-at.sh

echo ""

# 步骤 5: 最终验证
echo_info "步骤 5: 最终验证..."
cd "$PARENT_DIR"
source "$SCRIPT_DIR/config.sh"
./verify-relationships.sh

echo ""
echo_success "所有迁移步骤完成！"
echo ""
