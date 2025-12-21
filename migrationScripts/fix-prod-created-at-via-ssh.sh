#!/bin/bash

# 通过 SSH 在生产服务器上修复 created_at 时间戳
# 此脚本通过 SSH 连接到生产服务器，在 Docker 容器内执行修复 SQL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARBOURX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# 生产服务器配置
EC2_HOST="${EC2_HOST:-13.54.207.94}"
EC2_USER="${EC2_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-$HARBOURX_ROOT/harbourX-demo-key-pair.pem}"

# 数据库配置（Docker 容器内）
DB_CONTAINER="harbourx-postgres"
DB_USER="harbourx"
DB_NAME="harbourx"

echo ""
echo_info "=========================================="
echo_info "  通过 SSH 修复生产环境 created_at"
echo_info "  服务器: $EC2_HOST"
echo_info "=========================================="
echo ""

# 检查 SSH 密钥
if [ ! -f "$SSH_KEY" ]; then
    echo_error "SSH 密钥文件不存在: $SSH_KEY"
    exit 1
fi

# 设置 SSH 密钥权限
chmod 400 "$SSH_KEY" 2>/dev/null || true

# 测试 SSH 连接
echo_info "测试 SSH 连接..."
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "echo '连接成功'" > /dev/null 2>&1; then
    echo_error "无法连接到生产服务器"
    exit 1
fi
echo_success "SSH 连接成功"
echo ""

# 检查 Docker 容器
echo_info "检查 Docker 容器..."
CONTAINER_STATUS=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" \
    "cd /opt/harbourx && docker ps --format '{{.Names}}' | grep -q '^${DB_CONTAINER}$' && echo 'running' || echo 'not_running'" 2>&1)

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo_error "数据库容器未运行: $DB_CONTAINER"
    exit 1
fi
echo_success "数据库容器正在运行"
echo ""

# 执行修复
echo_info "开始修复 created_at 和 deleted_at 时间戳..."
echo ""

# 修复 broker_group_brokers
echo_info "Step 1: 修复 broker_group_brokers.created_at 和 deleted_at..."
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME}" << 'SQL'
-- 修复 broker_group_brokers.created_at
UPDATE broker_group_brokers bgb
SET created_at = (
    SELECT (
        (MIN(l.settled_date)::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        - INTERVAL '1 day'
    )
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
)
WHERE EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
);

-- 修复 broker_group_brokers.deleted_at
UPDATE broker_group_brokers bgb
SET deleted_at = NULL
WHERE bgb.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
    AND bgb.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND bgb.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
SQL

if [ $? -eq 0 ]; then
    echo_success "broker_group_brokers 修复完成"
else
    echo_error "broker_group_brokers 修复失败"
    exit 1
fi

echo ""

# 修复 aggregator_broker_groups
echo_info "Step 2: 修复 aggregator_broker_groups.created_at 和 deleted_at..."
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME}" << 'SQL'
-- 修复 aggregator_broker_groups.created_at
UPDATE aggregator_broker_groups abg
SET created_at = (
    SELECT (
        (MIN(l.settled_date)::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        - INTERVAL '1 day'
    )
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
)
WHERE EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
);

-- 修复 aggregator_broker_groups.deleted_at
UPDATE aggregator_broker_groups abg
SET deleted_at = NULL
WHERE abg.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
    AND abg.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND abg.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
SQL

if [ $? -eq 0 ]; then
    echo_success "aggregator_broker_groups 修复完成"
else
    echo_error "aggregator_broker_groups 修复失败"
    exit 1
fi

echo ""

# 验证修复结果
echo_info "Step 3: 验证修复结果..."
VERIFICATION_RESULT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -t -A -F'|'" << 'SQL'
SELECT 
    'broker_group_brokers' as table_name,
    COUNT(*) as total,
    COUNT(CASE WHEN EXISTS (
        SELECT 1 FROM loans l 
        WHERE l.broker_id = bgb.broker_id 
        AND l.settled_date IS NOT NULL 
        AND (
            bgb.created_at > (
                (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
            )
            OR (
                bgb.deleted_at IS NOT NULL 
                AND bgb.deleted_at <= (
                    (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
                )
            )
        )
    ) THEN 1 END) as problematic
FROM broker_group_brokers bgb
UNION ALL
SELECT 
    'aggregator_broker_groups' as table_name,
    COUNT(*) as total,
    COUNT(CASE WHEN EXISTS (
        SELECT 1 FROM loans l 
        WHERE l.broker_group_id = abg.broker_group_id 
        AND l.settled_date IS NOT NULL 
        AND (
            abg.created_at > (
                (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
            )
            OR (
                abg.deleted_at IS NOT NULL 
                AND abg.deleted_at <= (
                    (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
                )
            )
        )
    ) THEN 1 END) as problematic
FROM aggregator_broker_groups abg;
SQL
)

echo "$VERIFICATION_RESULT" | while IFS='|' read -r table_name total problematic; do
    if [ "$problematic" = "0" ]; then
        echo_success "$table_name: $total 个绑定，0 个有问题"
    else
        echo_error "$table_name: $total 个绑定，$problematic 个有问题"
    fi
done

echo ""
echo_success "修复完成！"
echo ""
echo "如果后端仍然报错，请："
echo "  1. 重启后端服务（清除缓存）"
echo "  2. 重新计算 commission transactions"
