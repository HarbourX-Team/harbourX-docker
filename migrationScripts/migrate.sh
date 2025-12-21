#!/bin/bash

# 统一数据迁移工具
# 支持本地和生产环境的完整迁移流程
#
# 用法:
#   ./migrate.sh local              # 迁移到本地环境
#   ./migrate.sh prod                 # 迁移到生产环境
#   ./migrate.sh clean-local          # 清理本地数据库
#   ./migrate.sh verify-local         # 验证本地数据
#   ./migrate.sh verify-prod          # 验证生产数据

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# 显示使用说明
show_usage() {
    echo ""
    echo_info "=========================================="
    echo_info "  统一数据迁移工具"
    echo_info "=========================================="
    echo ""
    echo "用法:"
    echo "  ./migrate.sh <command> [options]"
    echo ""
    echo "命令:"
    echo "  local             迁移数据到本地环境"
    echo "  prod              迁移数据到生产环境"
    echo "  clean-local       清理本地数据库"
    echo "  verify-local      验证本地数据"
    echo "  verify-prod       验证生产数据"
    echo "  clean-txt         清理所有 .txt 报告文件"
    echo ""
    echo "示例:"
    echo "  ./migrate.sh local"
    echo "  ./migrate.sh prod"
    echo "  ./migrate.sh clean-local"
    echo ""
}

# 清理本地数据库
clean_local_database() {
    echo ""
    echo_info "=========================================="
    echo_info "  清理本地数据库"
    echo_info "=========================================="
    echo ""
    
    DB_HOST="${LOCAL_DB_HOST:-localhost}"
    DB_PORT="${LOCAL_DB_PORT:-5432}"
    DB_USER="${LOCAL_DB_USER:-postgres}"
    DB_NAME="${LOCAL_DB_NAME:-harbourx}"
    DB_PASS="${LOCAL_DB_PASS:-postgres}"
    
    echo_info "数据库: $DB_NAME @ $DB_HOST:$DB_PORT"
    echo_warn "⚠️  警告：这将删除所有迁移的数据！"
    echo ""
    read -p "确认要继续吗？(yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        exit 0
    fi
    
    echo ""
    echo_info "开始清理数据库..."
    
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
-- 1. 删除关联表
TRUNCATE TABLE broker_group_brokers CASCADE;
TRUNCATE TABLE aggregator_broker_groups CASCADE;

-- 2. 删除brokers
TRUNCATE TABLE brokers CASCADE;

-- 3. 删除companies（包括broker groups）
DELETE FROM companies WHERE type IN (1, 2); -- 1=BROKER, 2=BROKER_GROUP
SQL
    
    echo_success "本地数据库清理完成"
    echo ""
}

# 清理所有 .txt 报告文件
clean_txt_reports() {
    echo ""
    echo_info "清理所有 .txt 报告文件..."
    
    cd "$SCRIPT_DIR"
    count=$(find . -maxdepth 1 -name "*.txt" -type f | wc -l | tr -d ' ')
    
    if [ "$count" -eq 0 ]; then
        echo_info "没有找到 .txt 文件"
    else
        find . -maxdepth 1 -name "*.txt" -type f -delete
        echo_success "已删除 $count 个 .txt 文件"
    fi
    echo ""
}

# 迁移到本地环境
migrate_to_local() {
    echo ""
    echo_info "=========================================="
    echo_info "  本地环境数据迁移"
    echo_info "=========================================="
    echo ""
    
    cd "$SCRIPT_DIR/migrate-to-local"
    
    # 设置默认登录信息
    export LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
    export LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
    
    source config.sh
    
    echo_info "使用账户: $LOGIN_EMAIL"
    echo_info "API地址: $API_BASE_URL"
    echo ""
    
    ./migrate.sh
    
    if [ $? -eq 0 ]; then
        echo ""
        echo_success "=========================================="
        echo_success "  本地迁移完成！"
        echo_success "=========================================="
        echo ""
    else
        echo_error "本地迁移失败"
        exit 1
    fi
}

# 迁移到生产环境
migrate_to_prod() {
    echo ""
    echo_info "=========================================="
    echo_info "  生产环境数据迁移"
    echo_info "=========================================="
    echo ""
    
    echo_warn "⚠️  警告: 您正在迁移到生产环境！"
    read -p "确认继续? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        exit 0
    fi
    
    cd "$SCRIPT_DIR/migrate-to-prod"
    
    # 检查生产环境密码
    if [ -z "$LOGIN_PASSWORD" ]; then
        echo_error "生产环境需要提供 LOGIN_PASSWORD"
        echo "请设置环境变量: export LOGIN_PASSWORD='your-password'"
        exit 1
    fi
    
    source config.sh
    
    echo_info "使用账户: $LOGIN_EMAIL"
    echo_info "API地址: $API_BASE_URL"
    echo ""
    
    ./migrate.sh
    
    if [ $? -eq 0 ]; then
        echo ""
        echo_success "=========================================="
        echo_success "  生产迁移完成！"
        echo_success "=========================================="
        echo ""
    else
        echo_error "生产迁移失败"
        exit 1
    fi
}

# 验证本地数据
verify_local() {
    echo ""
    echo_info "=========================================="
    echo_info "  验证本地数据"
    echo_info "=========================================="
    echo ""
    
    cd "$SCRIPT_DIR"
    
    # 验证 created_at
    echo_info "验证 created_at 修复状态..."
    ./verify-created-at.sh local
    echo ""
    
    # 验证关系
    echo_info "验证关系绑定..."
    ./verify-relationships.sh
    echo ""
    
    # 显示数据统计
    echo_info "数据统计:"
    DB_HOST="${LOCAL_DB_HOST:-localhost}"
    DB_PORT="${LOCAL_DB_PORT:-5432}"
    DB_USER="${LOCAL_DB_USER:-postgres}"
    DB_NAME="${LOCAL_DB_NAME:-harbourx}"
    DB_PASS="${LOCAL_DB_PASS:-postgres}"
    
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
SELECT 
    'Broker Groups' as type,
    COUNT(*) as count
FROM companies
WHERE type = 2
UNION ALL
SELECT 
    'Brokers' as type,
    COUNT(*) as count
FROM brokers;
SQL
    
    echo ""
    echo_success "本地数据验证完成"
    echo ""
}

# 验证生产数据
verify_prod() {
    echo ""
    echo_info "=========================================="
    echo_info "  验证生产数据"
    echo_info "=========================================="
    echo ""
    
    cd "$SCRIPT_DIR"
    
    # 验证 created_at
    echo_info "验证 created_at 修复状态..."
    ./verify-created-at.sh prod
    echo ""
    
    echo_success "生产数据验证完成"
    echo ""
}

# 主逻辑
COMMAND="${1:-}"

case "$COMMAND" in
    local)
        migrate_to_local
        ;;
    prod)
        migrate_to_prod
        ;;
    clean-local)
        clean_local_database
        ;;
    verify-local)
        verify_local
        ;;
    verify-prod)
        verify_prod
        ;;
    clean-txt)
        clean_txt_reports
        ;;
    ""|help|--help|-h)
        show_usage
        ;;
    *)
        echo_error "未知命令: $COMMAND"
        echo ""
        show_usage
        exit 1
        ;;
esac
