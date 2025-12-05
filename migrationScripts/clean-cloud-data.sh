#!/bin/bash

# 清理云端所有数据的脚本
# 删除所有 Broker Groups 和 Brokers
#
# 使用方法:
#   ./clean-cloud-data.sh              # 交互式确认后清理
#   FORCE_DELETE=true ./clean-cloud-data.sh  # 跳过确认，直接清理

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

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 配置变量
API_BASE_URL="${API_BASE_URL:-http://13.54.207.94/api}"
LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"

echo_warn "=========================================="
echo_warn "  清理云端所有数据"
echo_warn "  API: $API_BASE_URL"
echo_warn "=========================================="
echo ""
echo_warn "⚠️  警告: 此操作将删除云端所有 Broker Groups 和 Brokers！"
echo ""

# 如果设置了 FORCE_DELETE 环境变量，跳过确认
if [ "${FORCE_DELETE:-false}" != "true" ]; then
    read -p "确认要继续吗？(输入 'YES' 继续): " confirm
    if [ "$confirm" != "YES" ]; then
        echo_info "操作已取消"
        exit 0
    fi
else
    echo_info "FORCE_DELETE=true，跳过确认，直接删除"
fi

# 检查必需的工具
command -v jq >/dev/null 2>&1 || { echo_error "jq 未安装，请先安装: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo_error "curl 未安装"; exit 1; }

# 获取认证 token
echo_info "获取认证 token..."
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

# 删除所有 Brokers
echo ""
echo_info "步骤 1: 删除所有 Brokers..."
BROKERS_RESPONSE=$(call_api "GET" "/broker" "")
BROKER_IDS=$(echo "$BROKERS_RESPONSE" | jq -r '.data.brokers[]?.id // .data.brokers[].id // empty' 2>/dev/null)

BROKER_COUNT=0
BROKER_SUCCESS=0
BROKER_FAILED=0

if [ -n "$BROKER_IDS" ]; then
    BROKER_COUNT=$(echo "$BROKER_IDS" | wc -l | tr -d ' ')
    echo_info "找到 $BROKER_COUNT 个 Brokers"
    
    for broker_id in $BROKER_IDS; do
        if [ -z "$broker_id" ] || [ "$broker_id" = "null" ]; then
            continue
        fi
        
        echo_info "删除 Broker ID: $broker_id"
        DELETE_RESPONSE=$(call_api "DELETE" "/broker/$broker_id" "")
        DELETE_CODE=$(echo "$DELETE_RESPONSE" | jq -r '.code // empty' 2>/dev/null)
        
        if [ "$DELETE_CODE" = "0" ] || [ -z "$DELETE_CODE" ]; then
            echo_success "  ✅ Broker ID $broker_id 已删除"
            ((BROKER_SUCCESS++))
        else
            echo_error "  ❌ Broker ID $broker_id 删除失败: $DELETE_RESPONSE"
            ((BROKER_FAILED++))
        fi
    done
else
    echo_info "未找到任何 Brokers"
fi

echo ""
echo_info "Brokers 删除完成: 成功=$BROKER_SUCCESS, 失败=$BROKER_FAILED"

# 删除所有 Broker Groups
echo ""
echo_info "步骤 2: 删除所有 Broker Groups..."
COMPANIES_RESPONSE=$(call_api "GET" "/company?type=BROKER_GROUP" "")
COMPANY_IDS=$(echo "$COMPANIES_RESPONSE" | jq -r '.data.companies[]?.id // .data.companies[].id // empty' 2>/dev/null)

COMPANY_COUNT=0
COMPANY_SUCCESS=0
COMPANY_FAILED=0

if [ -n "$COMPANY_IDS" ]; then
    COMPANY_COUNT=$(echo "$COMPANY_IDS" | wc -l | tr -d ' ')
    echo_info "找到 $COMPANY_COUNT 个 Broker Groups"
    
    for company_id in $COMPANY_IDS; do
        if [ -z "$company_id" ] || [ "$company_id" = "null" ]; then
            continue
        fi
        
        echo_info "删除 Broker Group ID: $company_id"
        DELETE_RESPONSE=$(call_api "DELETE" "/company/$company_id" "")
        DELETE_CODE=$(echo "$DELETE_RESPONSE" | jq -r '.code // empty' 2>/dev/null)
        
        if [ "$DELETE_CODE" = "0" ] || [ -z "$DELETE_CODE" ]; then
            echo_success "  ✅ Broker Group ID $company_id 已删除"
            ((COMPANY_SUCCESS++))
        else
            echo_error "  ❌ Broker Group ID $company_id 删除失败: $DELETE_RESPONSE"
            ((COMPANY_FAILED++))
        fi
    done
else
    echo_info "未找到任何 Broker Groups"
fi

echo ""
echo_info "Broker Groups 删除完成: 成功=$COMPANY_SUCCESS, 失败=$COMPANY_FAILED"

# 总结
echo ""
echo_success "=========================================="
echo_success "  清理完成"
echo_success "=========================================="
echo ""
echo_info "删除统计:"
echo "  - Brokers: 成功=$BROKER_SUCCESS, 失败=$BROKER_FAILED"
echo "  - Broker Groups: 成功=$COMPANY_SUCCESS, 失败=$COMPANY_FAILED"
echo ""
