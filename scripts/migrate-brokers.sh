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
API_BASE_URL="${API_BASE_URL:-http://localhost:8080/api}"
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_USER="${OLD_DB_USER:-haimoney}"
OLD_DB_NAME="${OLD_DB_NAME:-haimoney}"

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

ID_MAPPING_FILE="$TMP_DIR/id_mapping.txt"

# 检查 ID 映射文件是否存在
if [ -f "id_mapping.txt" ]; then
    cp id_mapping.txt "$ID_MAPPING_FILE"
    echo_info "使用现有的 ID 映射文件: id_mapping.txt"
else
    echo_warn "ID 映射文件不存在，将创建新的映射文件"
    touch "$ID_MAPPING_FILE"
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

# 迁移 NON_DIRECT_PAYMENT Broker（来自 broker 表）
echo ""
echo_info "开始迁移 NON_DIRECT_PAYMENT Broker（来自 broker 表）..."

BROKERS_CSV="$TMP_DIR/brokers.csv"

PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" \
    -c "SELECT id, name, broker_group_id, infinity_id
        FROM broker
        WHERE deleted IS NULL
          AND (sub_broker_id IS NULL OR sub_broker_id = 0)
          AND (broker_group_id IS NOT NULL AND broker_group_id != 0)" \
    -t -A -F"," > "$BROKERS_CSV"

BROKER_COUNT=$(wc -l < "$BROKERS_CSV" | tr -d ' ')
echo_info "找到 $BROKER_COUNT 个 NON_DIRECT_PAYMENT broker 需要迁移"

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
    crn="123_${old_id}"
    
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
    if echo "$response" | jq -e '.data.id // .id' >/dev/null 2>&1; then
        new_id=$(echo "$response" | jq -r '.data.id // .id')
        echo_success "Broker ID $old_id -> $new_id: $name"
        ((SUCCESS_COUNT++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        echo_warn "Broker ID $old_id 已存在: $name"
        ((SKIPPED_COUNT++))
    else
        echo_error "Broker ID $old_id 迁移失败: $name"
        echo "  响应: $response"
        ((FAILED_COUNT++))
    fi
done < "$BROKERS_CSV"

echo ""
echo_info "NON_DIRECT_PAYMENT Broker 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"

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
    
    crn="123_SUB_${old_id}"
    
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
    
    # 构建 extra_info JSON（不包含 abn，只包含 address, phone, deduct, account_name）
    extra_info=$(jq -n \
        --arg address "$address" \
        --arg phone "$phone" \
        --arg deduct "$deduct" \
        --arg account_name "$account_name" \
        '{} +
        (if $address != "" and $address != "NULL" then {address: $address} else {} end) +
        (if $phone != "" and $phone != "NULL" then {phone: $phone} else {} end) +
        (if $deduct != "" and $deduct != "NULL" and $deduct != "false" then {deduct: ($deduct == "true" or $deduct == "t")} else {} end) +
        (if $account_name != "" and $account_name != "NULL" then {accountName: $account_name} else {} end)')
    
    # 构建 JSON（包含 name 字段，bsb_number 和 account_number 作为直接字段）
    json=$(jq -n \
        --arg email "$email" \
        --arg name "$name" \
        --arg type "DIRECT_PAYMENT" \
        --arg crn "$crn" \
        --argjson broker_group_id "$new_broker_group_id" \
        --arg infinity_id_str "$infinity_id" \
        --arg bsb_str "$bsb_clean" \
        --arg account_str "$account_clean" \
        --argjson extra_info "$extra_info" \
        '{
          email: $email,
          name: $name,
          type: $type,
          crn: $crn,
          brokerGroupId: $broker_group_id
        } + (if $infinity_id_str != "" and $infinity_id_str != "0" and $infinity_id_str != "NULL" then {infinityId: ($infinity_id_str | tonumber)} else {} end) +
          (if $bsb_str != "" then {bankAccountBsb: ($bsb_str | tonumber)} else {} end) +
          (if $account_str != "" then {bankAccountNumber: ($account_str | tonumber)} else {} end) +
          (if ($extra_info | length) > 0 then {extraInfo: $extra_info} else {} end)')
    
    # 调用 API
    response=$(call_api "POST" "/broker" "$json")
    
    # 检查响应
    if echo "$response" | jq -e '.data.id // .id' >/dev/null 2>&1; then
        new_id=$(echo "$response" | jq -r '.data.id // .id')
        echo_success "Sub-Broker ID $old_id -> $new_id: $name"
        ((SUCCESS_COUNT++))
    elif echo "$response" | grep -q "already exists\|duplicate"; then
        echo_warn "Sub-Broker ID $old_id 已存在: $name"
        ((SKIPPED_COUNT++))
    else
        echo_error "Sub-Broker ID $old_id 迁移失败: $name"
        echo "  响应: $response"
        ((FAILED_COUNT++))
    fi
done < "$SUB_BROKERS_CSV"

echo ""
echo_info "DIRECT_PAYMENT Broker 迁移完成:"
echo "  成功: $SUCCESS_COUNT"
echo "  跳过: $SKIPPED_COUNT"
echo "  失败: $FAILED_COUNT"

echo ""
echo_success "所有 Broker 迁移完成！"

