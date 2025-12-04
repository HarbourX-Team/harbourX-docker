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

# 配置变量
API_BASE_URL="${API_BASE_URL:-http://localhost:8080/api}"
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_USER="${OLD_DB_USER:-haimoney}"
OLD_DB_NAME="${OLD_DB_NAME:-haimoney}"
AGGREGATOR_COMPANY_ID="${AGGREGATOR_COMPANY_ID:-1}"

# 检查必需的工具
command -v jq >/dev/null 2>&1 || { echo_error "jq 未安装，请先安装: brew install jq"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo_error "psql 未安装，请先安装"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo_error "curl 未安装"; exit 1; }

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

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.token // .token // empty' 2>/dev/null)

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

ID_MAPPING_FILE="id_mapping.txt"

# 如果 ID 映射文件不存在，创建它
if [ ! -f "$ID_MAPPING_FILE" ]; then
    touch "$ID_MAPPING_FILE"
    echo_info "创建新的 ID 映射文件: $ID_MAPPING_FILE"
else
    echo_info "使用现有的 ID 映射文件: $ID_MAPPING_FILE"
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

PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, name, abn, account_name, bsb_number, account_number,
        email, phone, address
        FROM companies
        WHERE type = 2 AND deleted IS NULL" \
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
        echo "$old_id:$existing_id" >> "$ID_MAPPING_FILE"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # 构建 JSON
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
    if echo "$response" | jq -e '.data.id // .id' >/dev/null 2>&1; then
        new_id=$(echo "$response" | jq -r '.data.id // .id')
        echo_success "Broker Group ID $old_id -> $new_id: $name"
        echo "$old_id:$new_id" >> "$ID_MAPPING_FILE"
        ((SUCCESS_COUNT++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        # 如果已存在，尝试查找并记录映射
        existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo "")
        if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
            echo_warn "Broker Group ID $old_id 已存在 (新 ID: $existing_id): $name"
            echo "$old_id:$existing_id" >> "$ID_MAPPING_FILE"
        else
            echo_warn "Broker Group ID $old_id 已存在但无法找到 ID: $name"
        fi
        ((SKIPPED_COUNT++))
    else
        echo_error "Broker Group ID $old_id 迁移失败: $name"
        echo "  响应: $response"
        ((FAILED_COUNT++))
    fi
done < "$BROKER_GROUPS_CSV"

echo ""
echo_info "Broker Group 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"
echo ""
echo_success "ID 映射已保存到: $ID_MAPPING_FILE"

