#!/bin/bash

# 完整数据迁移脚本
# 按照 DATA_MIGRATION_STRUCTURE.md 规则迁移所有数据
# 迁移顺序：1. Broker Groups, 2. Brokers

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo_info "=========================================="
echo_info "  完整数据迁移脚本"
echo_info "  根据 DATA_MIGRATION_STRUCTURE.md"
echo_info "=========================================="
echo ""

# 检查必需的环境变量
if [ -z "$OLD_DB_PASS" ]; then
    echo_error "请设置环境变量 OLD_DB_PASS"
    echo "例如: export OLD_DB_PASS=\"your_password\""
    exit 1
fi

# 步骤 1: 迁移 Broker Groups
echo_info "步骤 1: 迁移 Broker Groups..."
echo ""
"$SCRIPT_DIR/migrate-broker-groups.sh"

if [ $? -ne 0 ]; then
    echo_error "Broker Groups 迁移失败，停止迁移"
    exit 1
fi

echo ""
echo_success "Broker Groups 迁移完成"
echo ""

# 检查 ID 映射文件
if [ ! -f "id_mapping.txt" ]; then
    echo_error "ID 映射文件不存在: id_mapping.txt"
    echo_error "Broker Groups 迁移可能失败"
    exit 1
fi

MAPPING_COUNT=$(wc -l < id_mapping.txt | tr -d ' ')
echo_info "ID 映射文件包含 $MAPPING_COUNT 个映射关系"
echo ""

# 步骤 2: 迁移 Brokers
echo_info "步骤 2: 迁移 Brokers..."
echo ""
"$SCRIPT_DIR/migrate-brokers.sh"

if [ $? -ne 0 ]; then
    echo_error "Brokers 迁移失败"
    exit 1
fi

echo ""
echo_success "所有数据迁移完成！"
echo ""
echo_info "迁移结果:"
echo "  - ID 映射文件: id_mapping.txt"
echo "  - 包含 Broker Group ID 映射关系"
echo ""

