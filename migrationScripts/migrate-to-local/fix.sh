#!/bin/bash

# 本地/生产环境 created_at/deleted_at 修复脚本（单文件版）
# 用法：
#   本地: ./fix.sh
#   生产: ./fix.sh prod

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo_info(){ echo -e "${YELLOW}$1${NC}"; }
echo_ok(){ echo -e "${GREEN}$1${NC}"; }
echo_err(){ echo -e "${RED}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-local}"
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true

if [ "$MODE" = "prod" ]; then
  # 生产环境：优先使用 K8S port-forward；若未配置则回退 SSH
  # 若存在 migrate-to-prod/config.sh，则加载其中的 K8S/SSH 变量
  if [ -f "$SCRIPT_DIR/../migrate-to-prod/config.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../migrate-to-prod/config.sh" 2>/dev/null || true
  fi

  # K8S 模式（当设置了 KUBECONFIG_FILE 或 PROD_KUBECONFIG_FILE 且有 kubectl）
  PROD_KUBECONFIG_FILE="${PROD_KUBECONFIG_FILE:-$KUBECONFIG_FILE}"
  if command -v kubectl >/dev/null 2>&1 && [ -n "$PROD_KUBECONFIG_FILE" ] && [ -f "$PROD_KUBECONFIG_FILE" ] && [ -n "${PROD_DB_SERVICE:-$KUBERNETES_SERVICE}" ]; then
    export KUBECONFIG="$PROD_KUBECONFIG_FILE"
    NS_OPT=""; [ -n "$PROD_DB_NAMESPACE" ] && NS_OPT="-n $PROD_DB_NAMESPACE"
    SVC_NAME="${PROD_DB_SERVICE:-${KUBERNETES_SERVICE:-broker-db}}"
    LOCAL_PORT="${PROD_DB_LOCAL_PORT:-${PORT_FORWARD_PORT:-6543}}"
    echo_info "Using K8S port-forward to service: $SVC_NAME (namespace: ${PROD_DB_NAMESPACE:-default}), local:$LOCAL_PORT -> 5432"
    if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then lsof -ti:$LOCAL_PORT | xargs kill -9 2>/dev/null || true; sleep 2; fi
    kubectl $NS_OPT port-forward svc/$SVC_NAME "$LOCAL_PORT:5432" >/dev/null 2>&1 & PF_PID=$!; sleep 3
    if ! kill -0 $PF_PID 2>/dev/null; then 
      echo_err "port-forward 启动失败，回退到 SSH 模式"
      kill $PF_PID 2>/dev/null || true
      # 继续执行 SSH 模式
    else
    trap 'kill $PF_PID 2>/dev/null || true; wait $PF_PID 2>/dev/null || true' EXIT INT TERM

    DB_HOST=localhost; DB_PORT=$LOCAL_PORT; DB_USER="${PROD_DB_USER:-harbourx}"; DB_NAME="${PROD_DB_NAME:-harbourx}"; DB_PASS="${PROD_DB_PASS}"
    [ -n "$DB_PASS" ] || { echo_err "缺少 PROD_DB_PASS（K8S 本地转发需要密码）"; exit 1; }
    echo_info "Fixing via psql on $DB_HOST:$DB_PORT/$DB_NAME ..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A << 'SQL'
UPDATE brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE companies SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE type = 2 AND created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE broker_group_brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE broker_group_brokers SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
UPDATE aggregator_broker_groups SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE aggregator_broker_groups SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
SQL
      echo_ok "=== Production Fix Complete (K8S) ==="
      exit 0
    fi
  fi

  # SSH 回退模式
  HARBOURX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  EC2_HOST="${EC2_HOST:-13.54.207.94}"; EC2_USER="${EC2_USER:-ec2-user}"; SSH_KEY="${SSH_KEY:-$HARBOURX_ROOT/harbourX-demo-key-pair.pem}"
  DB_CONTAINER="${DB_CONTAINER:-harbourx-postgres}"; DB_USER="${DB_USER:-harbourx}"; DB_NAME="${DB_NAME:-harbourx}"
  [ -f "$SSH_KEY" ] || { echo_err "SSH 密钥文件不存在: $SSH_KEY"; exit 1; }
  chmod 400 "$SSH_KEY" 2>/dev/null || true
  echo_info "Testing SSH connectivity to ${EC2_HOST}..."
  ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "echo 'ok'" >/dev/null 2>&1 || { echo_err "无法连接到生产服务器"; exit 1; }
  echo_ok "SSH OK\n"
  echo_info "Fixing created_at/deleted_at on production via SSH..."
  ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "cd /opt/harbourx && docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME}" << 'SQL'
UPDATE brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE companies SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE type = 2 AND created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE broker_group_brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE broker_group_brokers SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
UPDATE aggregator_broker_groups SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE aggregator_broker_groups SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
SQL
  echo_ok "=== Production Fix Complete (SSH) ==="
  exit 0
fi

# 本地修复
LOCAL_DB_HOST="${LOCAL_DB_HOST:-localhost}"; LOCAL_DB_PORT="${LOCAL_DB_PORT:-5432}"; LOCAL_DB_USER="${LOCAL_DB_USER:-postgres}"; LOCAL_DB_NAME="${LOCAL_DB_NAME:-harbourx}"; LOCAL_DB_PASS="${LOCAL_DB_PASS:-postgres}"
echo_ok "=== Fix Local Database created_at Timestamps ===\n"
echo_info "Testing database connection..."
if ! PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then echo_err "Cannot connect to local database"; exit 1; fi
echo_ok "✓ Database connection successful\n"

echo_info "Step 1: Fix brokers.created_at to 2000-01-01..."
set +e
PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A << 'SQL'
UPDATE brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
SQL

echo_info "Step 2: Fix broker groups (companies type=2).created_at to 2000-01-01..."
PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A << 'SQL'
UPDATE companies SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE type = 2 AND created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
SQL

echo_info "Step 3: Fix broker_group_brokers.created_at to 2000-01-01 and clear deleted_at..."
PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A << 'SQL'
UPDATE broker_group_brokers SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE broker_group_brokers SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
SQL

echo_info "Step 4: Fix aggregator_broker_groups.created_at to 2000-01-01 and clear deleted_at..."
PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A << 'SQL'
UPDATE aggregator_broker_groups SET created_at = '2000-01-01 00:00:00+00'::timestamp with time zone WHERE created_at != '2000-01-01 00:00:00+00'::timestamp with time zone;
UPDATE aggregator_broker_groups SET deleted_at = NULL WHERE deleted_at IS NOT NULL;
SQL
set -e

echo_ok "=== Local Fix Complete ==="
echo_info "如仍有问题，可重新运行或检查 loans 数据是否已导入"
