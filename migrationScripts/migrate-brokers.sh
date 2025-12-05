#!/bin/bash

# Broker 数据迁移脚本
# 根据新的数据库规则（name 字段为必填）迁移 broker 数据

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

echo_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 配置变量
API_BASE_URL="${API_BASE_URL:-http://13.54.207.94/api}"
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_USER="${OLD_DB_USER:-postgres}"
OLD_DB_NAME="${OLD_DB_NAME:-broker}"
ACR_CRN_MAPPING_FILE="${ACR_CRN_MAPPING_FILE:-acr_crn_mapping.csv}"

# Kubernetes port-forward 配置（如果老数据库在 Kubernetes 中）
USE_PORT_FORWARD="${USE_PORT_FORWARD:-false}"
# 支持选择环境：staging 或 production
ENVIRONMENT="${ENVIRONMENT:-staging}"
if [ "$ENVIRONMENT" = "production" ] || [ "$ENVIRONMENT" = "prod" ]; then
    KUBECONFIG_FILE="${KUBECONFIG_FILE:-../../haimoney/haimoney-infrastructure/connection-file/haimoney-commissions-cluster-PROD-kubeconfig.yaml}"
    echo_info "使用生产环境 (production)"
else
    KUBECONFIG_FILE="${KUBECONFIG_FILE:-../../haimoney/haimoney-infrastructure/connection-file/haimoney-staging-cluster-kubeconfig.yaml}"
    echo_info "使用测试环境 (staging)"
fi
KUBERNETES_SERVICE="${KUBERNETES_SERVICE:-broker-db}"
PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-5434}"
PORT_FORWARD_PID=""

# 尝试从 haimoney/start_env.sh 加载配置
HAIMONEY_ENV_FILE="${HAIMONEY_ENV_FILE:-../haimoney/start_env.sh}"
if [ -f "$HAIMONEY_ENV_FILE" ]; then
    # 使用 source 加载环境变量（但只读取，不执行其他命令）
    set -a
    source "$HAIMONEY_ENV_FILE" 2>/dev/null || true
    set +a
    
    # 从 haimoney 配置中读取数据库信息
    if [ -n "$DB_HOST" ]; then
        OLD_DB_HOST="$DB_HOST"
    fi
    if [ -n "$DB_PORT" ]; then
        OLD_DB_PORT="$DB_PORT"
    fi
    if [ -n "$DB_USER" ]; then
        OLD_DB_USER="$DB_USER"
    fi
    if [ -n "$DB_PW" ]; then
        OLD_DB_PASS="${OLD_DB_PASS:-$DB_PW}"
    fi
    # DB_NAME 在 haimoney 中是 'broker'
    if [ -n "$DB_NAME" ]; then
        OLD_DB_NAME="$DB_NAME"
    fi
    echo_success "已从 haimoney 配置加载数据库连接信息"
fi

# 清理函数：确保退出时关闭 port-forward
cleanup() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo_info "关闭 port-forward (PID: $PORT_FORWARD_PID)..."
        kill $PORT_FORWARD_PID 2>/dev/null || true
        wait $PORT_FORWARD_PID 2>/dev/null || true
        PORT_FORWARD_PID=""
    fi
}
trap cleanup EXIT INT TERM

# 检查必需的工具
command -v jq >/dev/null 2>&1 || { echo_error "jq 未安装，请先安装: brew install jq"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo_error "psql 未安装，请先安装"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo_error "curl 未安装"; exit 1; }

# 如果需要使用 port-forward，检查 kubectl
if [ "$USE_PORT_FORWARD" = "true" ]; then
    command -v kubectl >/dev/null 2>&1 || { echo_error "kubectl 未安装，请先安装"; exit 1; }
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        echo_error "KUBECONFIG 文件不存在: $KUBECONFIG_FILE"
        echo "请设置正确的 KUBECONFIG_FILE 环境变量"
        exit 1
    fi
    export KUBECONFIG="$KUBECONFIG_FILE"
    echo_info "使用 Kubernetes port-forward 连接数据库"
    echo_info "KUBECONFIG: $KUBECONFIG_FILE"
    echo_info "Service: $KUBERNETES_SERVICE"
    echo_info "本地端口: $PORT_FORWARD_PORT"
    
    # 检查端口是否已被占用
    if lsof -Pi :$PORT_FORWARD_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo_warn "端口 $PORT_FORWARD_PORT 已被占用，尝试关闭现有连接..."
        lsof -ti:$PORT_FORWARD_PORT | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
    
    # 启动 port-forward
    echo_info "启动 port-forward: $KUBERNETES_SERVICE -> localhost:$PORT_FORWARD_PORT"
    kubectl port-forward "svc/$KUBERNETES_SERVICE" "$PORT_FORWARD_PORT:5432" >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    
    # 检查 port-forward 是否成功
    if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
        echo_error "port-forward 启动失败"
        exit 1
    fi
    
    # 更新数据库连接信息
    OLD_DB_HOST="localhost"
    OLD_DB_PORT="$PORT_FORWARD_PORT"
    echo_success "port-forward 已启动 (PID: $PORT_FORWARD_PID)"
fi

# 获取认证 token
echo_info "获取认证 token..."
LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"

LOGIN_RESPONSE=$(curl -s -X POST "${API_BASE_URL%/api}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"identityType\": \"EMAIL\",
        \"identity\": \"${LOGIN_EMAIL}\",
        \"password\": \"${LOGIN_PASSWORD}\"
    }")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.jwt // .data.token // .token // empty' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo_error "登录失败，无法获取 token"
    echo "响应: $LOGIN_RESPONSE"
    exit 1
fi

echo_success "登录成功"

# 检查老数据库连接
echo_info "检查老数据库连接..."
if ! PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
    echo_error "无法连接到老数据库"
    echo "请检查环境变量: OLD_DB_HOST, OLD_DB_PORT, OLD_DB_USER, OLD_DB_NAME, OLD_DB_PASS"
    exit 1
fi

echo_success "老数据库连接正常"

# 创建临时目录
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# 根据 API_BASE_URL 生成映射文件名，确保不同环境使用不同的映射文件
if [[ "$API_BASE_URL" == *"localhost"* ]] || [[ "$API_BASE_URL" == *"127.0.0.1"* ]]; then
    SOURCE_MAPPING_FILE="id_mapping_local.txt"
else
    SOURCE_MAPPING_FILE="id_mapping.txt"
fi

ID_MAPPING_FILE="$TMP_DIR/id_mapping.txt"

# 检查 ID 映射文件是否存在
if [ -f "$SOURCE_MAPPING_FILE" ]; then
    cp "$SOURCE_MAPPING_FILE" "$ID_MAPPING_FILE"
    echo_info "使用现有的 ID 映射文件: $SOURCE_MAPPING_FILE (目标环境: $API_BASE_URL)"
else
    echo_warn "ID 映射文件不存在 ($SOURCE_MAPPING_FILE)，将创建新的映射文件"
    touch "$ID_MAPPING_FILE"
fi

# 如果设置了 FORCE_NEW_MAPPING，强制使用新的映射文件
if [ "${FORCE_NEW_MAPPING:-false}" = "true" ]; then
    echo_warn "FORCE_NEW_MAPPING=true，将忽略现有映射文件，创建新的映射"
    > "$ID_MAPPING_FILE"
fi

# API 调用函数
call_api() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -z "$data" ]; then
        curl -s -X "$method" "${API_BASE_URL}${endpoint}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json"
    else
        curl -s -X "$method" "${API_BASE_URL}${endpoint}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$data"
    fi
}

# 从 ACR Register 查找 CRN
get_crn_from_acr() {
    local broker_name="$1"
    
    if [ ! -f "$ACR_CRN_MAPPING_FILE" ]; then
        echo ""
        return
    fi
    
    # 使用 CSV 解析，处理带引号的字段
    # 尝试精确匹配
    local crn=$(awk -F',' -v name="$broker_name" '
        BEGIN {
            # 移除 CSV 字段中的引号
            gsub(/^"|"$/, "", name)
        }
        NR > 1 {
            # 移除字段中的引号
            gsub(/^"|"$/, "", $1)
            gsub(/^"|"$/, "", $2)
            if ($1 == name) {
                print $2
                exit
            }
        }
    ' "$ACR_CRN_MAPPING_FILE")
    
    echo "$crn"
}

# 加载 ACR Register CRN 映射
if [ -f "$ACR_CRN_MAPPING_FILE" ]; then
    echo_info "使用 ACR Register CRN 映射文件: $ACR_CRN_MAPPING_FILE"
    ACR_MAPPING_COUNT=$(tail -n +2 "$ACR_CRN_MAPPING_FILE" | wc -l | tr -d ' ')
    echo_info "ACR Register 中有 $ACR_MAPPING_COUNT 条 CRN 映射"
else
    echo_warn "ACR Register CRN 映射文件不存在: $ACR_CRN_MAPPING_FILE"
    echo_warn "将使用默认 CRN 格式: CRN_BROKER_{old_id}"
fi

# 迁移 NON_DIRECT_PAYMENT Broker（来自 broker 表）
echo ""
echo_info "开始迁移 NON_DIRECT_PAYMENT Broker（来自 broker 表）..."

BROKERS_CSV="$TMP_DIR/brokers.csv"

PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, name, broker_group_id, infinity_id
        FROM broker
        WHERE deleted IS NULL
          AND (sub_broker_id IS NULL OR sub_broker_id = 0)
          AND (broker_group_id IS NOT NULL AND broker_group_id != 0)
          AND id NOT IN (SELECT DISTINCT sub_broker_id FROM broker WHERE sub_broker_id IS NOT NULL AND sub_broker_id != 0)" \
    -t -A -F"," > "$BROKERS_CSV"

BROKER_COUNT=$(wc -l < "$BROKERS_CSV" | tr -d ' ')
echo_info "找到 $BROKER_COUNT 个 NON_DIRECT_PAYMENT broker 需要迁移"

NON_DIRECT_SUCCESS=0
NON_DIRECT_FAILED=0
NON_DIRECT_SKIPPED=0

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

while IFS=',' read -r old_id name broker_group_id infinity_id || [ -n "$old_id" ]; do
    # 跳过空行
    [ -z "$old_id" ] && continue
    
    # 清理字段
    old_id=$(echo "$old_id" | tr -d ' ')
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    broker_group_id=$(echo "$broker_group_id" | tr -d ' ')
    infinity_id=$(echo "$infinity_id" | tr -d ' ')
    
    # 检查 name 是否为空
    if [ -z "$name" ] || [ "$name" = "NULL" ]; then
        echo_warn "跳过 broker ID $old_id: name 为空"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 从 name 生成 email
    name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
    email="${name_clean}_${old_id}@migrated.local"
    
    # 从 ACR Register 查找 CRN，如果找不到则使用默认格式
    crn=$(get_crn_from_acr "$name")
    if [ -z "$crn" ]; then
        crn="CRN_BROKER_${old_id}"
        echo_warn "Broker ID $old_id ($name): 未在 ACR Register 中找到 CRN，使用默认值: $crn"
    else
        echo_info "Broker ID $old_id ($name): 找到 CRN: $crn"
    fi
    
    # 映射 broker_group_id
    new_broker_group_id=$(grep "^${broker_group_id}:" "$ID_MAPPING_FILE" | cut -d: -f2 | head -1)
    
    if [ -z "$new_broker_group_id" ]; then
        echo_warn "跳过 broker ID $old_id: 无法找到 broker_group_id $broker_group_id 的映射"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 构建 JSON（包含 name 字段）
    json=$(jq -n \
        --arg email "$email" \
        --arg name "$name" \
        --arg type "NON_DIRECT_PAYMENT" \
        --arg crn "$crn" \
        --argjson broker_group_id "$new_broker_group_id" \
        --argjson infinity_id "${infinity_id:-null}" \
        '{
          email: $email,
          name: $name,
          type: $type,
          crn: $crn,
          brokerGroupId: $broker_group_id
        } + (if $infinity_id != "null" and $infinity_id != "0" and $infinity_id != "" then {infinityId: ($infinity_id | tonumber)} else {} end)')
    
    # 调用 API
    response=$(call_api "POST" "/broker" "$json")
    
    # 检查响应
    # API 返回格式: {"data":{"brokers":[{"id":...}]},"code":0}
    if echo "$response" | jq -e '.data.brokers[0].id // .data.id // .id' >/dev/null 2>&1; then
        new_id=$(echo "$response" | jq -r '.data.brokers[0].id // .data.id // .id')
        echo_success "Broker ID $old_id -> $new_id: $name"
        ((SUCCESS_COUNT++))
        ((NON_DIRECT_SUCCESS++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        echo_warn "Broker ID $old_id 已存在: $name"
        ((SKIPPED_COUNT++))
        ((NON_DIRECT_SKIPPED++))
    else
        echo_error "Broker ID $old_id 迁移失败: $name"
        echo "  响应: $response"
        ((FAILED_COUNT++))
        ((NON_DIRECT_FAILED++))
    fi
done < "$BROKERS_CSV"

echo ""
echo_info "NON_DIRECT_PAYMENT Broker 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"

# 保存 NON_DIRECT_PAYMENT 统计
NON_DIRECT_SUCCESS=$SUCCESS_COUNT
NON_DIRECT_SKIPPED=$SKIPPED_COUNT
NON_DIRECT_FAILED=$FAILED_COUNT

# 迁移 DIRECT_PAYMENT Broker（来自 sub_broker 表）
echo ""
echo_info "开始迁移 DIRECT_PAYMENT Broker（来自 sub_broker 表）..."

SUB_BROKERS_CSV="$TMP_DIR/sub_brokers.csv"

PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, email, name, broker_group_id, infinity_id,
        bsb_number, account_number, abn, address, phone, deduct, account_name
        FROM sub_broker
        WHERE deleted IS NULL" \
    -t -A -F"," > "$SUB_BROKERS_CSV"

SUB_BROKER_COUNT=$(wc -l < "$SUB_BROKERS_CSV" | tr -d ' ')
echo_info "找到 $SUB_BROKER_COUNT 个 DIRECT_PAYMENT broker 需要迁移"

DIRECT_SUCCESS=0
DIRECT_FAILED=0
DIRECT_SKIPPED=0

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

while IFS=',' read -r old_id email name broker_group_id infinity_id \
    bsb_number account_number abn address phone deduct account_name || [ -n "$old_id" ]; do
    # 跳过空行
    [ -z "$old_id" ] && continue
    
    # 清理字段
    old_id=$(echo "$old_id" | tr -d ' ')
    email=$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    broker_group_id=$(echo "$broker_group_id" | tr -d ' ')
    infinity_id=$(echo "$infinity_id" | tr -d ' ')
    bsb_number=$(echo "$bsb_number" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    account_number=$(echo "$account_number" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    abn=$(echo "$abn" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    address=$(echo "$address" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    phone=$(echo "$phone" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    deduct=$(echo "$deduct" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    account_name=$(echo "$account_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 检查 name 是否为空
    if [ -z "$name" ] || [ "$name" = "NULL" ]; then
        echo_warn "跳过 sub_broker ID $old_id: name 为空"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 处理 email：如果为空，从 name 生成
    if [ -z "$email" ] || [ "$email" = "NULL" ]; then
        name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
        email="${name_clean}_${old_id}@migrated.local"
    fi
    
    # 从 ACR Register 查找 CRN，如果找不到则使用默认格式
    crn=$(get_crn_from_acr "$name")
    if [ -z "$crn" ]; then
        crn="CRN_SUB_BROKER_${old_id}"
        echo_warn "Sub-Broker ID $old_id ($name): 未在 ACR Register 中找到 CRN，使用默认值: $crn"
    else
        echo_info "Sub-Broker ID $old_id ($name): 找到 CRN: $crn"
    fi
    
    # 清理 BSB 和 account number
    bsb_clean=$(echo "$bsb_number" | tr -d -c '0-9')
    account_clean=$(echo "$account_number" | tr -d -c '0-9')
    
    # 映射 broker_group_id
    new_broker_group_id=$(grep "^${broker_group_id}:" "$ID_MAPPING_FILE" | cut -d: -f2 | head -1)
    
    if [ -z "$new_broker_group_id" ]; then
        echo_warn "跳过 sub_broker ID $old_id: 无法找到 broker_group_id $broker_group_id 的映射"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 清理字段值（将 "NULL" 转换为空字符串）
    abn_clean=$(if [ "$abn" = "NULL" ] || [ -z "$abn" ]; then echo ""; else echo "$abn"; fi)
    address_clean=$(if [ "$address" = "NULL" ] || [ -z "$address" ]; then echo ""; else echo "$address"; fi)
    phone_clean=$(if [ "$phone" = "NULL" ] || [ -z "$phone" ]; then echo ""; else echo "$phone"; fi)
    account_name_clean=$(if [ "$account_name" = "NULL" ] || [ -z "$account_name" ]; then echo ""; else echo "$account_name"; fi)
    
    # 构建 JSON（包含 name 字段，bsb_number 和 account_number 作为直接字段，abn/address/phone/accountName 作为单独字段）
    json=$(jq -n \
        --arg email "$email" \
        --arg name "$name" \
        --arg type "DIRECT_PAYMENT" \
        --arg crn "$crn" \
        --argjson broker_group_id "$new_broker_group_id" \
        --arg infinity_id_str "$infinity_id" \
        --arg bsb_str "$bsb_clean" \
        --arg account_str "$account_clean" \
        --arg abn "$abn_clean" \
        --arg address "$address_clean" \
        --arg phone "$phone_clean" \
        --arg account_name "$account_name_clean" \
        '{
          email: $email,
          name: $name,
          type: $type,
          crn: $crn,
          brokerGroupId: $broker_group_id
        } + (if $infinity_id_str != "" and $infinity_id_str != "0" and $infinity_id_str != "NULL" then {infinityId: ($infinity_id_str | tonumber)} else {} end) +
          (if $bsb_str != "" then {bankAccountBsb: ($bsb_str | tonumber)} else {} end) +
          (if $account_str != "" then {bankAccountNumber: ($account_str | tonumber)} else {} end) +
          (if $abn != "" then {abn: $abn} else {} end) +
          (if $address != "" then {address: $address} else {} end) +
          (if $phone != "" then {phone: $phone} else {} end) +
          (if $account_name != "" then {accountName: $account_name} else {} end)')
    
    # 调用 API
    response=$(call_api "POST" "/broker" "$json")
    
    # 检查响应
    # API 返回格式: {"data":{"brokers":[{"id":...}]},"code":0}
    if echo "$response" | jq -e '.data.brokers[0].id // .data.id // .id' >/dev/null 2>&1; then
        new_id=$(echo "$response" | jq -r '.data.brokers[0].id // .data.id // .id')
        echo_success "Sub-Broker ID $old_id -> $new_id: $name"
        ((SUCCESS_COUNT++))
        ((DIRECT_SUCCESS++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        echo_warn "Sub-Broker ID $old_id 已存在: $name"
        ((SKIPPED_COUNT++))
        ((DIRECT_SKIPPED++))
    else
        echo_error "Sub-Broker ID $old_id 迁移失败: $name"
        echo "  响应: $response"
        ((FAILED_COUNT++))
        ((DIRECT_FAILED++))
    fi
done < "$SUB_BROKERS_CSV"

echo ""
echo_info "DIRECT_PAYMENT Broker 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"

# 保存 DIRECT_PAYMENT 统计
DIRECT_SUCCESS=$SUCCESS_COUNT
DIRECT_SKIPPED=$SKIPPED_COUNT
DIRECT_FAILED=$FAILED_COUNT

echo ""
echo_success "所有 Broker 迁移完成！"

# 生成迁移报告
generate_broker_report() {
    echo_info "生成 Broker 迁移报告..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORT_FILE="$SCRIPT_DIR/broker-report-${TIMESTAMP}.txt"
    
    # 获取认证 token（用于查询云端数据）
    LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
    LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
    
    LOGIN_RESPONSE=$(curl -s -X POST "${API_BASE_URL%/api}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"identityType\": \"EMAIL\",
            \"identity\": \"${LOGIN_EMAIL}\",
            \"password\": \"${LOGIN_PASSWORD}\"
        }")
    
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.jwt // .data.token // .token // empty' 2>/dev/null)
    
    # API 调用函数
    call_api() {
        local method=$1
        local endpoint=$2
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            echo ""
            return
        fi
        curl -s -X "$method" "${API_BASE_URL}${endpoint}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json"
    }
    
    # 查询云端 Brokers 数量
    CLOUD_BROKERS_TOTAL=0
    CLOUD_BROKERS_DIRECT=0
    CLOUD_BROKERS_NON_DIRECT=0
    
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        BROKERS_RESPONSE=$(call_api "GET" "/broker")
        if [ -n "$BROKERS_RESPONSE" ]; then
            CLOUD_BROKERS_TOTAL=$(echo "$BROKERS_RESPONSE" | jq -r '.data.brokers | length' 2>/dev/null || echo "0")
            CLOUD_BROKERS_DIRECT=$(echo "$BROKERS_RESPONSE" | jq -r '[.data.brokers[]? | select(.type == "DIRECT_PAYMENT" or .type == 1)] | length' 2>/dev/null || echo "0")
            CLOUD_BROKERS_NON_DIRECT=$(echo "$BROKERS_RESPONSE" | jq -r '[.data.brokers[]? | select(.type == "NON_DIRECT_PAYMENT" or .type == 2)] | length' 2>/dev/null || echo "0")
        fi
    fi
    
    # 查询老数据库统计
    OLD_DB_NON_DIRECT=0
    OLD_DB_DIRECT=0
    
    if [ -n "$OLD_DB_PASS" ]; then
        set +e
        # NON_DIRECT_PAYMENT brokers
        OLD_DB_NON_DIRECT=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
            -c "SELECT COUNT(*) FROM broker WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0) AND id NOT IN (SELECT DISTINCT sub_broker_id FROM broker WHERE sub_broker_id IS NOT NULL AND sub_broker_id != 0);" \
            -t -A 2>/dev/null | tr -d ' ' || echo "0")
        
        # DIRECT_PAYMENT brokers (sub_broker)
        OLD_DB_DIRECT=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
            -c "SELECT COUNT(*) FROM sub_broker WHERE deleted IS NULL;" \
            -t -A 2>/dev/null | tr -d ' ' || echo "0")
        set -e
    fi
    
    # 生成报告
    {
        echo "# Broker 迁移报告"
        echo "# 生成时间: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# 数据来源: ${ENVIRONMENT:-staging} 环境"
        echo "# 目标环境: ${API_BASE_URL}"
        echo ""
        echo "## 迁移统计"
        echo ""
        echo "### NON_DIRECT_PAYMENT Brokers"
        echo "- **成功**: ${NON_DIRECT_SUCCESS}个"
        echo "- **跳过**: ${NON_DIRECT_SKIPPED}个"
        echo "- **失败**: ${NON_DIRECT_FAILED}个"
        echo ""
        echo "### DIRECT_PAYMENT Brokers"
        echo "- **成功**: ${DIRECT_SUCCESS}个"
        echo "- **跳过**: ${DIRECT_SKIPPED}个"
        echo "- **失败**: ${DIRECT_FAILED}个"
        echo ""
        echo "### 总计"
        TOTAL_SUCCESS=$((NON_DIRECT_SUCCESS + DIRECT_SUCCESS))
        TOTAL_SKIPPED=$((NON_DIRECT_SKIPPED + DIRECT_SKIPPED))
        TOTAL_FAILED=$((NON_DIRECT_FAILED + DIRECT_FAILED))
        echo "- **成功**: ${TOTAL_SUCCESS}个"
        echo "- **跳过**: ${TOTAL_SKIPPED}个"
        echo "- **失败**: ${TOTAL_FAILED}个"
        echo ""
        echo "---"
        echo ""
        echo "## 数据状态"
        echo ""
        echo "### 老数据库（${ENVIRONMENT:-staging}）"
        echo "- **NON_DIRECT_PAYMENT Brokers**: ${OLD_DB_NON_DIRECT}个"
        echo "- **DIRECT_PAYMENT Brokers**: ${OLD_DB_DIRECT}个"
        echo "- **总计**: $((OLD_DB_NON_DIRECT + OLD_DB_DIRECT))个"
        echo ""
        echo "### 云端（HarbourX）"
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            echo "- **Brokers (总计)**: ${CLOUD_BROKERS_TOTAL}个"
            echo "  - DIRECT_PAYMENT: ${CLOUD_BROKERS_DIRECT}个"
            echo "  - NON_DIRECT_PAYMENT: ${CLOUD_BROKERS_NON_DIRECT}个"
        else
            echo "- **Brokers**: 无法查询（认证失败）"
        fi
        echo ""
        echo "---"
        echo ""
        echo "## 相关文件"
        echo ""
        echo "- **ID 映射文件**: ${SOURCE_MAPPING_FILE:-id_mapping.txt}"
        echo "- **报告文件**: $REPORT_FILE"
        if [ -n "$ACR_CRN_MAPPING_FILE" ] && [ -f "$ACR_CRN_MAPPING_FILE" ]; then
            echo "- **CRN 映射文件**: $ACR_CRN_MAPPING_FILE"
        fi
        echo ""
        echo "---"
        echo ""
        echo "## 环境信息"
        echo ""
        echo "- **环境**: ${ENVIRONMENT:-staging}"
        echo "- **API 地址**: ${API_BASE_URL}"
        echo "- **ID 映射文件**: ${SOURCE_MAPPING_FILE:-id_mapping.txt}"
        echo ""
        if [ "$TOTAL_FAILED" -gt 0 ]; then
            echo "## 失败记录"
            echo ""
            echo "⚠️  有 ${TOTAL_FAILED} 个 Brokers 迁移失败"
            echo "  - NON_DIRECT_PAYMENT: ${NON_DIRECT_FAILED}个"
            echo "  - DIRECT_PAYMENT: ${DIRECT_FAILED}个"
            echo ""
            echo "请检查迁移日志获取详细失败信息"
            echo ""
        fi
    } > "$REPORT_FILE"
    
    echo_success "Broker 迁移报告已生成: $REPORT_FILE"
}

# 生成报告
generate_broker_report



