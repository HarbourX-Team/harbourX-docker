#!/bin/bash
# 清理本地数据库中的所有迁移数据

set -e

DB_HOST="${LOCAL_DB_HOST:-localhost}"
DB_PORT="${LOCAL_DB_PORT:-5432}"
DB_USER="${LOCAL_DB_USER:-postgres}"
DB_NAME="${LOCAL_DB_NAME:-harbourx}"
DB_PASS="${LOCAL_DB_PASS:-postgres}"

echo "=========================================="
echo "清理本地数据库"
echo "数据库: $DB_NAME @ $DB_HOST:$DB_PORT"
echo "=========================================="
echo ""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}⚠️  警告：这将删除所有迁移的数据！${NC}"
echo ""
read -p "确认要继续吗？(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "开始清理数据库..."

# 按顺序删除数据（考虑外键约束）
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'SQL'
-- 禁用外键检查（PostgreSQL没有这个，需要按顺序删除）

-- 1. 删除关联表
TRUNCATE TABLE broker_group_brokers CASCADE;
TRUNCATE TABLE aggregator_broker_groups CASCADE;

-- 2. 删除brokers
TRUNCATE TABLE brokers CASCADE;

-- 3. 删除companies（包括broker groups）
DELETE FROM companies WHERE type IN (1, 2); -- 1=BROKER, 2=BROKER_GROUP

-- 4. 删除其他相关数据（如果有）
TRUNCATE TABLE loans CASCADE;
TRUNCATE TABLE commission_transactions CASCADE;
TRUNCATE TABLE fee_models CASCADE;
TRUNCATE TABLE commission_models CASCADE;
TRUNCATE TABLE clients CASCADE;

-- 重置序列（如果需要）
-- ALTER SEQUENCE companies_id_seq RESTART WITH 1;
-- ALTER SEQUENCE brokers_id_seq RESTART WITH 1;
SQL

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 数据库清理完成！${NC}"
    echo ""
    echo "已清理的表："
    echo "  - broker_group_brokers"
    echo "  - aggregator_broker_groups"
    echo "  - brokers"
    echo "  - companies (type 1, 2)"
    echo "  - loans"
    echo "  - commission_transactions"
    echo "  - fee_models"
    echo "  - commission_models"
    echo "  - clients"
else
    echo -e "${RED}❌ 数据库清理失败！${NC}"
    exit 1
fi
