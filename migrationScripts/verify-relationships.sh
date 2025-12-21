#!/bin/bash

# 验证迁移后的关系是否正确建立
# 检查 broker groups 和 aggregator 的关系，以及 brokers 和 broker groups 的关系

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
if [ -f "$SCRIPT_DIR/migrate-to-local/config.sh" ]; then
    source "$SCRIPT_DIR/migrate-to-local/config.sh"
fi

# 数据库配置
LOCAL_DB_HOST="${LOCAL_DB_HOST:-localhost}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-5432}"
LOCAL_DB_USER="${LOCAL_DB_USER:-postgres}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-harbourx}"
LOCAL_DB_PASS="${LOCAL_DB_PASS:-postgres}"

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
echo_info "  验证迁移关系"
echo_info "=========================================="
echo ""

# 检查 broker groups 和 aggregator 的关系
echo_info "检查 Broker Groups 和 Aggregator 的关系..."
BROKER_GROUPS_TOTAL=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" \
    -t -A -c "SELECT COUNT(*) FROM companies WHERE type = 2;" 2>/dev/null || echo "0")

BROKER_GROUPS_LINKED=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" \
    -t -A -c "SELECT COUNT(DISTINCT c.id) FROM companies c JOIN aggregator_broker_groups abg ON abg.broker_group_id = c.id WHERE c.type = 2 AND abg.aggregator_id = 1;" 2>/dev/null || echo "0")

if [ "$BROKER_GROUPS_TOTAL" = "$BROKER_GROUPS_LINKED" ] && [ "$BROKER_GROUPS_TOTAL" != "0" ]; then
    echo_success "所有 $BROKER_GROUPS_TOTAL 个 Broker Groups 都已关联到 aggregator_id=1"
else
    echo_warn "Broker Groups: $BROKER_GROUPS_TOTAL 个总数，$BROKER_GROUPS_LINKED 个已关联"
    UNLINKED_COUNT=$((BROKER_GROUPS_TOTAL - BROKER_GROUPS_LINKED))
    if [ "$UNLINKED_COUNT" -gt 0 ]; then
        echo_warn "有 $UNLINKED_COUNT 个 Broker Groups 未关联到 aggregator_id=1，正在修复..."
        
        # 自动修复：将所有未关联的 broker groups 关联到 aggregator_id=1
        PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" << 'SQL'
INSERT INTO aggregator_broker_groups (aggregator_id, broker_group_id, created_at)
SELECT 
    1 as aggregator_id,
    c.id as broker_group_id,
    NOW() as created_at
FROM companies c
WHERE c.type = 2
AND NOT EXISTS (
    SELECT 1 
    FROM aggregator_broker_groups abg 
    WHERE abg.aggregator_id = 1 
    AND abg.broker_group_id = c.id
)
ON CONFLICT DO NOTHING;
SQL
        
        echo_success "已修复未关联的 Broker Groups"
    fi
fi

echo ""

# 检查 brokers 和 broker groups 的关系
echo_info "检查 Brokers 和 Broker Groups 的关系..."
BROKERS_TOTAL=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" \
    -t -A -c "SELECT COUNT(*) FROM brokers;" 2>/dev/null || echo "0")

BROKERS_LINKED=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" \
    -t -A -c "SELECT COUNT(DISTINCT b.id) FROM brokers b JOIN broker_group_brokers bgb ON bgb.broker_id = b.id;" 2>/dev/null || echo "0")

if [ "$BROKERS_TOTAL" = "$BROKERS_LINKED" ] && [ "$BROKERS_TOTAL" != "0" ]; then
    echo_success "所有 $BROKERS_TOTAL 个 Brokers 都已关联到 broker groups"
else
    echo_warn "Brokers: $BROKERS_TOTAL 个总数，$BROKERS_LINKED 个已关联"
    UNLINKED_COUNT=$((BROKERS_TOTAL - BROKERS_LINKED))
    if [ "$UNLINKED_COUNT" -gt 0 ]; then
        echo_warn "有 $UNLINKED_COUNT 个 Brokers 未关联到 broker groups（这可能是正常的，如果这些是测试数据）"
    fi
fi

echo ""
echo_success "关系验证完成"
echo ""
