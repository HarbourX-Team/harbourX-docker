#!/bin/bash

# 诊断生产环境的 MISSING_AGGREGATOR 错误
# 通过 SSH 连接到生产服务器，检查 aggregator_broker_groups 的 created_at 问题

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
echo_info "  诊断生产环境 MISSING_AGGREGATOR 错误"
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

# 诊断 aggregator_broker_groups 问题
echo_info "检查 aggregator_broker_groups 的 created_at 问题..."
echo ""

DIAGNOSTIC_RESULT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" \
    "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -t -A -F'|'" << 'SQL'
-- 检查有问题的 aggregator_broker_groups 绑定
SELECT 
    abg.id as binding_id,
    abg.aggregator_id,
    abg.broker_group_id,
    abg.created_at,
    abg.deleted_at,
    l.id as loan_id,
    l.settled_date,
    (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    ) as settled_instant,
    CASE 
        WHEN abg.created_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        ) THEN 'created_at_after_settled'
        WHEN abg.deleted_at IS NOT NULL AND abg.deleted_at <= (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        ) THEN 'deleted_at_before_settled'
        ELSE 'ok'
    END as issue_type
FROM aggregator_broker_groups abg
INNER JOIN loans l ON l.broker_group_id = abg.broker_group_id
WHERE l.settled_date IS NOT NULL
AND l.broker_group_id IS NOT NULL
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
ORDER BY l.settled_date DESC, abg.created_at DESC
LIMIT 20;
SQL
)

if [ -z "$DIAGNOSTIC_RESULT" ] || [ "$DIAGNOSTIC_RESULT" = "" ]; then
    echo_success "未发现 aggregator_broker_groups 的 created_at 问题"
    echo ""
    echo_info "可能的原因："
    echo "  1. 问题已修复"
    echo "  2. 错误来自其他原因（如缺少 aggregator 记录本身）"
    echo ""
    echo_info "建议检查："
    echo "  1. 后端日志中的具体错误信息"
    echo "  2. 是否存在对应的 aggregator 记录"
    echo "  3. aggregator_broker_groups 绑定是否存在"
else
    echo_error "发现以下有问题的绑定："
    echo ""
    echo "binding_id | aggregator_id | broker_group_id | loan_id | settled_date | issue_type"
    echo "-----------|---------------|-----------------|---------|--------------|------------"
    echo "$DIAGNOSTIC_RESULT" | while IFS='|' read -r binding_id aggregator_id broker_group_id created_at deleted_at loan_id settled_date settled_instant issue_type; do
        echo "$binding_id | $aggregator_id | $broker_group_id | $loan_id | $settled_date | $issue_type"
    done
    echo ""
    echo_warn "发现 $(echo "$DIAGNOSTIC_RESULT" | wc -l | tr -d ' ') 个有问题的绑定"
    echo ""
    echo_info "建议运行修复脚本："
    echo "  ./fix-prod-created-at-via-ssh.sh"
fi

echo ""

# 检查最近创建的绑定（可能是 RCTI 上传后新创建的）
echo_info "检查最近创建的 aggregator_broker_groups 绑定（最近 24 小时）..."
echo ""

RECENT_BINDINGS=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" \
    "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -t -A -F'|'" << 'SQL'
SELECT 
    abg.id as binding_id,
    abg.aggregator_id,
    abg.broker_group_id,
    abg.created_at,
    COUNT(l.id) as loan_count,
    MIN(l.settled_date) as earliest_settled_date,
    MAX(l.settled_date) as latest_settled_date
FROM aggregator_broker_groups abg
LEFT JOIN loans l ON l.broker_group_id = abg.broker_group_id
WHERE abg.created_at > NOW() - INTERVAL '24 hours'
GROUP BY abg.id, abg.aggregator_id, abg.broker_group_id, abg.created_at
ORDER BY abg.created_at DESC
LIMIT 10;
SQL
)

if [ -n "$RECENT_BINDINGS" ] && [ "$RECENT_BINDINGS" != "" ]; then
    echo_warn "发现最近 24 小时内创建的绑定："
    echo ""
    echo "binding_id | aggregator_id | broker_group_id | created_at | loan_count | earliest_settled_date"
    echo "-----------|---------------|-----------------|------------|------------|---------------------"
    echo "$RECENT_BINDINGS" | while IFS='|' read -r binding_id aggregator_id broker_group_id created_at loan_count earliest_settled_date latest_settled_date; do
        echo "$binding_id | $aggregator_id | $broker_group_id | $created_at | $loan_count | $earliest_settled_date"
    done
    echo ""
    echo_warn "这些新创建的绑定可能有 created_at 问题，如果它们的 loan.settled_date 是过去的日期"
    echo ""
    echo_info "建议运行修复脚本："
    echo "  ./fix-prod-created-at-via-ssh.sh"
else
    echo_success "最近 24 小时内没有新创建的绑定"
fi

echo ""
echo_info "诊断完成"
