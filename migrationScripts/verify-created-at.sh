#!/bin/bash

# Script to verify created_at timestamp fixes
# Usage: ./verify-created-at.sh [local|prod]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENVIRONMENT="${1:-local}"

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

check_table() {
    local table_name=$1
    local query=$2
    local db_host=$3
    local db_port=$4
    local db_user=$5
    local db_name=$6
    local db_pass=$7
    
    echo_info "检查 ${table_name}.created_at..."
    
    # Execute query and get results (使用 -A -F'|' 确保正确解析)
    RESULT=$(PGPASSWORD="$db_pass" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -t -A -F'|' -c "$query" 2>/dev/null | head -1 | tr -d ' ')
    
    if [ -z "$RESULT" ]; then
        echo_error "${table_name}: 无法获取数据"
        return 1
    fi
    
    # 使用 | 作为分隔符解析
    TOTAL=$(echo "$RESULT" | awk -F'|' '{print $1}')
    PROBLEMATIC=$(echo "$RESULT" | awk -F'|' '{print $2}')
    
    # 如果解析失败，尝试空格分隔
    if [ -z "$TOTAL" ] || [ "$TOTAL" = "" ]; then
        TOTAL=$(echo "$RESULT" | awk '{print $1}')
        PROBLEMATIC=$(echo "$RESULT" | awk '{print $2}')
    fi
    
    if [ "$PROBLEMATIC" = "0" ] || [ -z "$PROBLEMATIC" ]; then
        echo_success "${table_name}: $TOTAL 个绑定，0 个有问题"
        return 0
    else
        echo_error "${table_name}: $TOTAL 个绑定，$PROBLEMATIC 个有问题"
        return 1
    fi
}

if [ "$ENVIRONMENT" = "local" ]; then
    echo_info "=== 验证本地数据库 created_at 修复状态 ==="
    echo ""
    
    DB_HOST="${LOCAL_DB_HOST:-localhost}"
    DB_PORT="${LOCAL_DB_PORT:-5432}"
    DB_USER="${LOCAL_DB_USER:-postgres}"
    DB_NAME="${LOCAL_DB_NAME:-harbourx}"
    DB_PASS="${LOCAL_DB_PASS:-postgres}"
    
    echo_info "数据库连接: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    echo ""
    
    # Check broker_group_brokers (both created_at and deleted_at issues)
    # 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
    QUERY="SELECT COUNT(*) as total, COUNT(CASE WHEN EXISTS (SELECT 1 FROM loans l WHERE l.broker_id = bgb.broker_id AND l.settled_date IS NOT NULL AND (bgb.created_at > ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone) OR (bgb.deleted_at IS NOT NULL AND bgb.deleted_at <= ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone)))) THEN 1 END) as problematic FROM broker_group_brokers bgb;"
    check_table "broker_group_brokers" "$QUERY" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_NAME" "$DB_PASS"
    
    # Check aggregator_broker_groups (both created_at and deleted_at issues)
    # 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
    QUERY="SELECT COUNT(*) as total, COUNT(CASE WHEN EXISTS (SELECT 1 FROM loans l WHERE l.broker_group_id = abg.broker_group_id AND l.settled_date IS NOT NULL AND l.broker_group_id IS NOT NULL AND (abg.created_at > ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone) OR (abg.deleted_at IS NOT NULL AND abg.deleted_at <= ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone)))) THEN 1 END) as problematic FROM aggregator_broker_groups abg;"
    check_table "aggregator_broker_groups" "$QUERY" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_NAME" "$DB_PASS"
    
    # Check loans data
    echo_info "检查 loans 数据..."
    LOANS_INFO=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT COUNT(*) as total, COUNT(CASE WHEN settled_date IS NOT NULL THEN 1 END) as with_settled_date FROM loans;
    " 2>/dev/null | head -1 | xargs)
    
    LOANS_TOTAL=$(echo "$LOANS_INFO" | awk '{print $1}')
    LOANS_WITH_DATE=$(echo "$LOANS_INFO" | awk '{print $2}')
    
    echo_info "Loans 数据: 总计 $LOANS_TOTAL，有 settled_date 的 $LOANS_WITH_DATE"
    
    if [ "$LOANS_TOTAL" = "0" ] || [ -z "$LOANS_TOTAL" ]; then
        echo_warn "当前没有 loans 数据，无法完全验证 created_at 修复"
        echo_warn "当有 loans 数据后，需要重新运行修复脚本"
    fi
    
    echo ""
    echo_success "本地数据库验证完成"
    
elif [ "$ENVIRONMENT" = "prod" ]; then
    echo_info "=== 验证生产数据库 created_at 修复状态 ==="
    echo ""
    
    if [ -z "$PROD_DB_PASS" ]; then
        echo_error "未配置 PROD_DB_PASS 环境变量"
        echo_warn "请设置以下环境变量："
        echo "  export PROD_DB_HOST=\"your-prod-db-host\""
        echo "  export PROD_DB_PORT=\"5432\""
        echo "  export PROD_DB_USER=\"postgres\""
        echo "  export PROD_DB_NAME=\"harbourx\""
        echo "  export PROD_DB_PASS=\"your-prod-db-password\""
        exit 1
    fi
    
    DB_HOST="${PROD_DB_HOST}"
    DB_PORT="${PROD_DB_PORT:-5432}"
    DB_USER="${PROD_DB_USER:-postgres}"
    DB_NAME="${PROD_DB_NAME:-harbourx}"
    DB_PASS="$PROD_DB_PASS"
    
    echo_info "数据库连接: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    echo ""
    
    # Check broker_group_brokers (both created_at and deleted_at issues)
    # 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
    QUERY="SELECT COUNT(*) as total, COUNT(CASE WHEN EXISTS (SELECT 1 FROM loans l WHERE l.broker_id = bgb.broker_id AND l.settled_date IS NOT NULL AND (bgb.created_at > ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone) OR (bgb.deleted_at IS NOT NULL AND bgb.deleted_at <= ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone)))) THEN 1 END) as problematic FROM broker_group_brokers bgb;"
    check_table "broker_group_brokers" "$QUERY" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_NAME" "$DB_PASS"
    
    # Check aggregator_broker_groups (both created_at and deleted_at issues)
    # 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
    QUERY="SELECT COUNT(*) as total, COUNT(CASE WHEN EXISTS (SELECT 1 FROM loans l WHERE l.broker_group_id = abg.broker_group_id AND l.settled_date IS NOT NULL AND l.broker_group_id IS NOT NULL AND (abg.created_at > ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone) OR (abg.deleted_at IS NOT NULL AND abg.deleted_at <= ((l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone)))) THEN 1 END) as problematic FROM aggregator_broker_groups abg;"
    check_table "aggregator_broker_groups" "$QUERY" "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_NAME" "$DB_PASS"
    
    # Check loans data
    echo_info "检查 loans 数据..."
    LOANS_INFO=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT COUNT(*) as total, COUNT(CASE WHEN settled_date IS NOT NULL THEN 1 END) as with_settled_date FROM loans;
    " 2>/dev/null | head -1 | xargs)
    
    LOANS_TOTAL=$(echo "$LOANS_INFO" | awk '{print $1}')
    LOANS_WITH_DATE=$(echo "$LOANS_INFO" | awk '{print $2}')
    
    echo_info "Loans 数据: 总计 $LOANS_TOTAL，有 settled_date 的 $LOANS_WITH_DATE"
    
    if [ "$LOANS_TOTAL" = "0" ] || [ -z "$LOANS_TOTAL" ]; then
        echo_warn "当前没有 loans 数据，无法完全验证 created_at 修复"
        echo_warn "当有 loans 数据后，需要重新运行修复脚本"
    fi
    
    echo ""
    echo_success "生产数据库验证完成"
    
else
    echo_error "无效的环境参数: $ENVIRONMENT"
    echo_info "用法: ./verify-created-at.sh [local|prod]"
    exit 1
fi

