#!/bin/bash

# Broker Group 数据迁移脚本
# 根据 DATA_MIGRATION_STRUCTURE.md 规则迁移 broker group 数据

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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 配置变量
# 默认使用生产环境 API，可以通过环境变量覆盖
API_BASE_URL="${API_BASE_URL:-http://13.54.207.94/api}"
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_USER="${OLD_DB_USER:-postgres}"
OLD_DB_NAME="${OLD_DB_NAME:-broker}"
AGGREGATOR_COMPANY_ID="${AGGREGATOR_COMPANY_ID:-1}"

# 根据 API_BASE_URL 生成映射文件名，确保不同环境使用不同的映射文件
if [[ "$API_BASE_URL" == *"localhost"* ]] || [[ "$API_BASE_URL" == *"127.0.0.1"* ]]; then
    ID_MAPPING_FILE="$SCRIPT_DIR/migration-report/migrate-local/id_mapping_local.txt"
else
    ID_MAPPING_FILE="$SCRIPT_DIR/migration-report/migrate-prod/id_mapping.txt"
fi

# 如果设置了 FORCE_NEW_MAPPING，强制使用新的映射文件
if [ "${FORCE_NEW_MAPPING:-false}" = "true" ]; then
    if [ -f "$ID_MAPPING_FILE" ]; then
        mv "$ID_MAPPING_FILE" "${ID_MAPPING_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        echo_warn "已备份现有映射文件，将创建新的映射文件"
    fi
fi

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
    echo_info "从 $HAIMONEY_ENV_FILE 加载配置..."
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

echo_info "API 地址: ${API_BASE_URL%/api}/api/auth/login"
echo_info "登录邮箱: ${LOGIN_EMAIL}"

# 使用 set +e 允许 curl 失败时不立即退出
set +e
LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_BASE_URL%/api}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"identityType\": \"EMAIL\",
        \"identity\": \"${LOGIN_EMAIL}\",
        \"password\": \"${LOGIN_PASSWORD}\"
    }" 2>&1)
CURL_EXIT_CODE=$?
set -e

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo_error "curl 请求失败 (退出码: $CURL_EXIT_CODE)"
    echo_error "请检查网络连接和 API 地址是否正确"
    echo_error "API 地址: ${API_BASE_URL%/api}/api/auth/login"
    exit 1
fi

# 分离响应体和 HTTP 状态码
HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo_error "登录失败，HTTP 状态码: $HTTP_CODE"
    echo_error "响应: $RESPONSE_BODY"
    exit 1
fi

TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.data.jwt // .data.token // .token // empty' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo_error "登录失败，无法获取 token"
    echo_error "响应: $RESPONSE_BODY"
    echo_error "请检查 LOGIN_EMAIL 和 LOGIN_PASSWORD 是否正确"
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

# ID_MAPPING_FILE 已在上面根据 API_BASE_URL 设置

# 如果 ID 映射文件不存在，创建它
if [ ! -f "$ID_MAPPING_FILE" ]; then
    touch "$ID_MAPPING_FILE"
    echo_info "创建新的 ID 映射文件: $ID_MAPPING_FILE (目标环境: $API_BASE_URL)"
else
    echo_info "使用现有的 ID 映射文件: $ID_MAPPING_FILE (目标环境: $API_BASE_URL)"
    # 如果设置了 FORCE_NEW_MAPPING，清理现有映射文件
    if [ "${FORCE_NEW_MAPPING:-false}" = "true" ]; then
        backup_file="${ID_MAPPING_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ID_MAPPING_FILE" "$backup_file"
        > "$ID_MAPPING_FILE"  # 清空文件
        echo_warn "已备份现有映射文件到: $backup_file，将创建新的映射"
    fi
fi

# 创建临时映射文件，避免重复写入
TEMP_MAPPING_FILE="${ID_MAPPING_FILE}.tmp"
> "$TEMP_MAPPING_FILE"  # 清空临时文件

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

# 查找已存在的 Broker Group（通过 name 或 abn）
find_existing_broker_group() {
    local name=$1
    local abn=$2
    
    # 尝试通过 ABN 查找（唯一，更快）
    if [ -n "$abn" ] && [ "$abn" != "0" ]; then
        local abn_clean=$(echo "$abn" | tr -d ' ')
        local abn_encoded=$(echo "$abn_clean" | sed 's/ /%20/g')
        set +e
        local response=$(call_api "GET" "/company?abn=${abn_encoded}" "" 2>/dev/null)
        local api_exit=$?
        set -e
        if [ $api_exit -eq 0 ]; then
            local id=$(echo "$response" | jq -r '.data.companies[0].id // empty' 2>/dev/null)
            if [ -n "$id" ] && [ "$id" != "null" ]; then
                echo "$id"
                return 0
            fi
        fi
    fi
    
    # 尝试通过 name 查找
    set +e
    local response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
    local api_exit=$?
    set -e
    
    if [ $api_exit -eq 0 ] && [ -n "$response" ]; then
        local name_escaped=$(echo "$name" | sed 's/"/\\"/g')
        local id=$(echo "$response" | jq -r ".data.companies[] | select(.name == \"$name_escaped\") | .id" 2>/dev/null | head -1)
        if [ -n "$id" ] && [ "$id" != "null" ]; then
            echo "$id"
            return 0
        fi
    fi
    
    return 1
}

# 迁移 Broker Groups
echo ""
echo_info "开始迁移 Broker Groups..."

BROKER_GROUPS_CSV="$TMP_DIR/broker_groups.csv"

# 查询所有 Broker Groups（包括 deleted 的，以便统计总数）
# 注意：老系统中使用 broker_group 表
PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE deleted IS NULL) as not_deleted, COUNT(*) FILTER (WHERE deleted IS NOT NULL) as deleted FROM broker_group;" \
    -t -A -F"," > "$TMP_DIR/broker_groups_count.txt" 2>/dev/null || true

if [ -f "$TMP_DIR/broker_groups_count.txt" ]; then
    TOTAL_COUNT=$(cut -d',' -f1 "$TMP_DIR/broker_groups_count.txt" | tr -d ' ')
    NOT_DELETED_COUNT=$(cut -d',' -f2 "$TMP_DIR/broker_groups_count.txt" | tr -d ' ')
    DELETED_COUNT=$(cut -d',' -f3 "$TMP_DIR/broker_groups_count.txt" | tr -d ' ')
    echo_info "Broker Groups 统计 (broker_group 表): 总计=$TOTAL_COUNT, 未删除=$NOT_DELETED_COUNT, 已删除=$DELETED_COUNT"
    
    if [ -n "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" != "0" ] && [ "$TOTAL_COUNT" -lt 144 ]; then
        echo_warn "注意: 生产环境显示有144个 Broker Groups，但数据库中只找到 $TOTAL_COUNT 个"
        echo_warn "可能的原因: 部分数据在其他数据库或需要不同的查询条件"
    fi
fi

# 查询所有未删除的 Broker Groups 进行迁移
# 注意：不限制 deleted IS NULL，先查询所有记录看看
PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, name, abn, account_name, bsb_number, account_number,
        email, phone, address, deleted
        FROM broker_group
        ORDER BY id" \
    -t -A -F"," > "$TMP_DIR/broker_groups_all.csv" 2>/dev/null || true

# 只迁移未删除的记录
PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, name, abn, account_name, bsb_number, account_number,
        email, phone, address
        FROM broker_group
        WHERE deleted IS NULL" \
    -t -A -F"," > "$BROKER_GROUPS_CSV"

BROKER_GROUP_COUNT=$(wc -l < "$BROKER_GROUPS_CSV" | tr -d ' ')
echo_info "找到 $BROKER_GROUP_COUNT 个 Broker Group 需要迁移"

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

while IFS=',' read -r old_id name abn account_name bsb account_number email phone address || [ -n "$old_id" ]; do
    # 跳过空行
    [ -z "$old_id" ] && continue
    
    # 清理字段
    old_id=$(echo "$old_id" | tr -d ' ')
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    abn=$(echo "$abn" | tr -d ' ')
    account_name=$(echo "$account_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    bsb=$(echo "$bsb" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    account_number=$(echo "$account_number" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    email=$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    phone=$(echo "$phone" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    address=$(echo "$address" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 检查必需字段
    if [ -z "$name" ] || [ "$name" = "NULL" ]; then
        echo_warn "跳过 Broker Group ID $old_id: name 为空"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 清理数据
    abn_clean=$(echo "$abn" | tr -d -c '0-9')
    bsb_clean=$(echo "$bsb" | tr -d -c '0-9')
    account_clean=$(echo "$account_number" | tr -d -c '0-9')
    
    # 设置默认值
    if [ -z "$abn_clean" ] || [ "$abn_clean" = "0" ]; then
        abn_clean="1000000000${old_id}"
        echo_warn "Broker Group ID $old_id: ABN 为空，使用默认值: $abn_clean"
    fi
    
    if [ -z "$account_name" ] || [ "$account_name" = "NULL" ]; then
        account_name="${name} Bank Account"
    fi
    
    if [ -z "$bsb_clean" ] || [ "$bsb_clean" = "0" ]; then
        bsb_clean="123456"
    fi
    
    if [ -z "$account_clean" ] || [ "$account_clean" = "0" ]; then
        account_clean="12345678"
    fi
    
    # 检查是否已存在
    existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo "")
    
    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        echo_warn "Broker Group ID $old_id 已存在 (新 ID: $existing_id): $name"
        # 使用临时文件，避免重复
        if ! grep -q "^${old_id}:" "$TEMP_MAPPING_FILE" 2>/dev/null; then
            echo "$old_id:$existing_id" >> "$TEMP_MAPPING_FILE"
        fi
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 构建 JSON（注意：companies 表没有 crn 字段，只有 abn）
    json=$(jq -n \
        --arg name "$name" \
        --argjson abn "$abn_clean" \
        --arg bank_account_name "$account_name" \
        --argjson bsb "$bsb_clean" \
        --argjson account "$account_clean" \
        --argjson aggregator_id "$AGGREGATOR_COMPANY_ID" \
        --arg email "$email" \
        --arg phone "$phone" \
        --arg address "$address" \
        '{
          name: $name,
          abn: $abn,
          bankAccountName: $bank_account_name,
          bankAccountBsb: $bsb,
          bankAccountNumber: $account,
          aggregatorCompanyId: $aggregator_id
        } + (if $email != "" and $email != "NULL" then {email: $email} else {} end) +
          (if $phone != "" and $phone != "NULL" then {phoneNumber: $phone} else {} end) +
          (if $address != "" and $address != "NULL" then {address: $address} else {} end)')
    
    # 调用 API
    response=$(call_api "POST" "/company/broker-group" "$json")
    
    # 检查响应
    response_code=$(echo "$response" | jq -r '.code // "unknown"' 2>/dev/null)
    new_id=$(echo "$response" | jq -r '.data.companies[0].id // empty' 2>/dev/null)
    
    # 详细检查：确保响应码为 0 且 ID 不为空
    if [ "$response_code" = "0" ] && [ -n "$new_id" ] && [ "$new_id" != "null" ] && [ "$new_id" != "" ]; then
        echo_success "Broker Group ID $old_id -> $new_id: $name"
        # 使用临时文件，避免重复，并验证ID是否真的存在
        if ! grep -q "^${old_id}:" "$TEMP_MAPPING_FILE" 2>/dev/null; then
            # 验证new_id是否真的在数据库中存在
            bg_exists=$(PGPASSWORD="${LOCAL_DB_PASS:-postgres}" psql -h "${LOCAL_DB_HOST:-localhost}" -p "${LOCAL_DB_PORT:-5432}" -U "${LOCAL_DB_USER:-postgres}" -d "${LOCAL_DB_NAME:-harbourx}" \
                -t -A -c "SELECT COUNT(*) FROM companies WHERE id = $new_id AND type = 2;" 2>/dev/null | tr -d ' ')
            if [ "$bg_exists" = "1" ]; then
                echo "$old_id:$new_id" >> "$TEMP_MAPPING_FILE"
            else
                echo_warn "警告：API返回ID $new_id 但数据库中不存在，跳过此映射"
            fi
        fi
        ((SUCCESS_COUNT++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        # 如果已存在，尝试查找并记录映射
        existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo "")
        if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
            echo_warn "Broker Group ID $old_id 已存在 (新 ID: $existing_id): $name"
            # 使用临时文件，避免重复
            if ! grep -q "^${old_id}:" "$TEMP_MAPPING_FILE" 2>/dev/null; then
                echo "$old_id:$existing_id" >> "$TEMP_MAPPING_FILE"
            fi
        else
            echo_warn "Broker Group ID $old_id 已存在但无法找到 ID: $name"
        fi
        ((SKIPPED_COUNT++))
    else
        echo_error "Broker Group ID $old_id 迁移失败: $name"
        echo "  响应码: $response_code"
        echo "  响应: $response"
        ((FAILED_COUNT++))
    fi
done < "$BROKER_GROUPS_CSV"

# 合并临时映射文件到主文件（去重）
if [ -f "$TEMP_MAPPING_FILE" ] && [ -s "$TEMP_MAPPING_FILE" ]; then
    # 读取临时文件中的映射，去重后追加到主文件
    while IFS=: read -r old_id new_id; do
        # 如果主文件中已有此old_id的映射，先删除旧的
        if grep -q "^${old_id}:" "$ID_MAPPING_FILE" 2>/dev/null; then
            sed -i.bak "/^${old_id}:/d" "$ID_MAPPING_FILE"
        fi
        # 添加新映射
        echo "$old_id:$new_id" >> "$ID_MAPPING_FILE"
    done < "$TEMP_MAPPING_FILE"
    
    # 清理临时文件
    rm -f "$TEMP_MAPPING_FILE"
fi

echo ""
echo_info "Broker Group 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"

# 验证并修复所有 broker groups 与 aggregator 的关联关系
echo ""
echo_info "验证并修复 Broker Groups 与 Aggregator 的关联关系..."

# 尝试从环境变量或配置文件加载本地数据库配置
if [ -z "$LOCAL_DB_HOST" ] && [ -f "$SCRIPT_DIR/migrate-to-local/config.sh" ]; then
    source "$SCRIPT_DIR/migrate-to-local/config.sh" 2>/dev/null || true
fi

# 检查本地数据库配置（如果是本地环境）
if [[ "$API_BASE_URL" == *"localhost"* ]] || [[ "$API_BASE_URL" == *"127.0.0.1"* ]]; then
    DB_HOST="${LOCAL_DB_HOST:-localhost}"
    DB_PORT="${LOCAL_DB_PORT:-5432}"
    DB_USER="${LOCAL_DB_USER:-postgres}"
    DB_NAME="${LOCAL_DB_NAME:-harbourx}"
    DB_PASS="${LOCAL_DB_PASS:-postgres}"
    
    UNLINKED_COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT COUNT(*) FROM companies c WHERE c.type = 2 AND NOT EXISTS (SELECT 1 FROM aggregator_broker_groups abg WHERE abg.broker_group_id = c.id AND abg.aggregator_id = ${AGGREGATOR_COMPANY_ID:-1});" 2>/dev/null || echo "0")
    
    if [ "$UNLINKED_COUNT" != "0" ] && [ -n "$UNLINKED_COUNT" ] && [ "$UNLINKED_COUNT" != "" ]; then
        echo_warn "发现 $UNLINKED_COUNT 个 Broker Groups 未关联到 aggregator_id=${AGGREGATOR_COMPANY_ID:-1}，正在自动修复..."
        
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << EOF
INSERT INTO aggregator_broker_groups (aggregator_id, broker_group_id, created_at)
SELECT 
    ${AGGREGATOR_COMPANY_ID:-1} as aggregator_id,
    c.id as broker_group_id,
    NOW() as created_at
FROM companies c
WHERE c.type = 2
AND NOT EXISTS (
    SELECT 1 
    FROM aggregator_broker_groups abg 
    WHERE abg.aggregator_id = ${AGGREGATOR_COMPANY_ID:-1}
    AND abg.broker_group_id = c.id
)
ON CONFLICT DO NOTHING;
EOF
        
        if [ $? -eq 0 ]; then
            echo_success "已自动修复 $UNLINKED_COUNT 个 Broker Groups 的关联关系"
        else
            echo_warn "自动修复失败，请手动运行 verify-relationships.sh"
        fi
    else
        echo_success "所有 Broker Groups 都已正确关联到 aggregator_id=${AGGREGATOR_COMPANY_ID:-1}"
    fi
else
    echo_info "非本地环境，跳过自动修复（生产环境请手动运行 verify-relationships.sh）"
fi
echo ""
echo_success "ID 映射已保存到: $ID_MAPPING_FILE"

# 生成迁移报告
generate_broker_group_report() {
    echo_info "生成 Broker Group 迁移报告..."
    
    # SCRIPT_DIR 已在脚本开头定义
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORT_FILE="$SCRIPT_DIR/broker-group-report-${TIMESTAMP}.txt"
    
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
    
    # 查询云端 Broker Groups 数量
    CLOUD_BROKER_GROUPS=0
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        COMPANIES_RESPONSE=$(call_api "GET" "/company?type=BROKER_GROUP")
        if [ -n "$COMPANIES_RESPONSE" ]; then
            CLOUD_BROKER_GROUPS=$(echo "$COMPANIES_RESPONSE" | jq -r '.data.companies | length' 2>/dev/null || echo "0")
        fi
    fi
    
    # 查询老数据库统计
    OLD_DB_TOTAL=0
    OLD_DB_NOT_DELETED=0
    OLD_DB_DELETED=0
    
    if [ -n "$OLD_DB_PASS" ]; then
        set +e
        DB_STATS=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
            -c "SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE deleted IS NULL) as not_deleted, COUNT(*) FILTER (WHERE deleted IS NOT NULL) as deleted FROM broker_group;" \
            -t -A -F"," 2>/dev/null)
        set -e
        
        if [ -n "$DB_STATS" ]; then
            OLD_DB_TOTAL=$(echo "$DB_STATS" | cut -d',' -f1 | tr -d ' ')
            OLD_DB_NOT_DELETED=$(echo "$DB_STATS" | cut -d',' -f2 | tr -d ' ')
            OLD_DB_DELETED=$(echo "$DB_STATS" | cut -d',' -f3 | tr -d ' ')
        fi
    fi
    
    # 生成报告
    {
        echo "# Broker Group 迁移报告"
        echo "# 生成时间: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# 数据来源: ${ENVIRONMENT:-staging} 环境"
        echo "# 目标环境: ${API_BASE_URL}"
        echo ""
        echo "## 迁移统计"
        echo ""
        echo "### 本次迁移结果"
        echo "- **成功**: ${SUCCESS_COUNT}个"
        echo "- **跳过**: ${SKIPPED_COUNT}个（已存在）"
        echo "- **失败**: ${FAILED_COUNT}个"
        echo ""
        echo "---"
        echo ""
        echo "## 数据状态"
        echo ""
        echo "### 老数据库（${ENVIRONMENT:-staging}）"
        echo "- **总计**: ${OLD_DB_TOTAL}个"
        echo "- **未删除**: ${OLD_DB_NOT_DELETED}个"
        echo "- **已删除**: ${OLD_DB_DELETED}个"
        echo ""
        echo "### 云端（HarbourX）"
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
            echo "- **Broker Groups**: ${CLOUD_BROKER_GROUPS}个"
        else
            echo "- **Broker Groups**: 无法查询（认证失败）"
        fi
        echo ""
        echo "---"
        echo ""
        echo "## 相关文件"
        echo ""
        echo "- **ID 映射文件**: $ID_MAPPING_FILE"
        echo "- **报告文件**: $REPORT_FILE"
        echo ""
        echo "---"
        echo ""
        echo "## 环境信息"
        echo ""
        echo "- **环境**: ${ENVIRONMENT:-staging}"
        echo "- **API 地址**: ${API_BASE_URL}"
        echo "- **映射文件**: $ID_MAPPING_FILE"
        if [ -f "$ID_MAPPING_FILE" ]; then
            MAPPING_COUNT=$(wc -l < "$ID_MAPPING_FILE" | tr -d ' ')
            echo "- **映射关系数**: ${MAPPING_COUNT}个"
        fi
        echo ""
        if [ "$FAILED_COUNT" -gt 0 ]; then
            echo "## 失败记录"
            echo ""
            echo "⚠️  有 ${FAILED_COUNT} 个 Broker Groups 迁移失败"
            echo "请检查迁移日志获取详细失败信息"
            echo ""
        fi
    } > "$REPORT_FILE"
    
    echo_success "Broker Group 迁移报告已生成: $REPORT_FILE"
}

# 生成报告
generate_broker_group_report



