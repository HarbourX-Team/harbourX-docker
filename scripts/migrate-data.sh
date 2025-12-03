#!/bin/bash

# 统一的数据迁移脚本 - 从旧 HaiMoney 系统迁移数据到新 HarbourX 系统
# 这是唯一的数据迁移脚本，整合了所有迁移功能
# 支持 Kubernetes port-forward 和直接数据库连接
#
# 使用方法:
#   bash scripts/migrate-data.sh
#   或设置环境变量:
#     OLD_DB_HOST=localhost OLD_DB_PORT=5432 OLD_DB_NAME=broker OLD_DB_USER=postgres OLD_DB_PASS=postgres bash scripts/migrate-data.sh
#
# 相关工具:
#   - scripts/check-migration-status.sh: 检查迁移状态和诊断问题
#   - scripts/set-aws-s3-credentials.sh: 设置 AWS S3 凭证（独立工具）
#
# 环境变量:
#   - OLD_DB_HOST: 旧数据库主机 (默认: localhost)
#   - OLD_DB_PORT: 旧数据库端口 (默认: 5432)
#   - OLD_DB_NAME: 旧数据库名称 (默认: broker)
#   - OLD_DB_USER: 旧数据库用户 (默认: postgres)
#   - OLD_DB_PASS: 旧数据库密码 (默认: postgres)
#   - API_BASE_URL: 新系统 API 地址 (默认: http://localhost:8080/api)
#   - LOGIN_EMAIL: 登录邮箱 (默认: haimoneySupport@harbourx.com.au)
#   - LOGIN_PASSWORD: 登录密码 (默认: password)
#   - AGGREGATOR_COMPANY_ID: Aggregator 公司 ID (默认: 1)
#   - SKIP_MIGRATION: 跳过迁移 (默认: false)
#   - KUBECONFIG_PATH: Kubernetes config 文件路径 (可选)
#   - KUBECTL_SERVICE: Kubernetes service 名称 (默认: broker-db)
#   - KUBECTL_PORT_FORWARD_PORT: Port-forward 端口 (默认: 5432)

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
API_BASE_URL="${API_BASE_URL:-http://localhost:8080/api}"
LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
AGGREGATOR_COMPANY_ID="${AGGREGATOR_COMPANY_ID:-1}"

# 旧系统数据库配置
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_NAME="${OLD_DB_NAME:-broker}"
OLD_DB_USER="${OLD_DB_USER:-postgres}"
OLD_DB_PASS="${OLD_DB_PASS:-postgres}"

# Kubernetes 配置（可选）
KUBECONFIG_PATH="${KUBECONFIG_PATH:-}"
KUBECTL_SERVICE="${KUBECTL_SERVICE:-broker-db}"
KUBECTL_PORT_FORWARD_PORT="${KUBECTL_PORT_FORWARD_PORT:-5432}"

# 跳过迁移标志
SKIP_MIGRATION="${SKIP_MIGRATION:-false}"

# Port-forward 进程 ID
PORT_FORWARD_PID=""

# 清理函数
cleanup() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo ""
        echo -e "${YELLOW}清理 port-forward (PID: $PORT_FORWARD_PID)...${NC}"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        wait $PORT_FORWARD_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo -e "${BLUE}🔄 数据迁移脚本${NC}"
echo -e "${BLUE}==================${NC}"
echo ""

# 检查是否跳过迁移
if [ "$SKIP_MIGRATION" = "true" ]; then
    echo -e "${YELLOW}⚠️  跳过数据迁移 (SKIP_MIGRATION=true)${NC}"
    exit 0
fi

# 检查必需的工具
MISSING_TOOLS=""
for tool in curl jq; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}❌ 缺少必需工具:${MISSING_TOOLS}${NC}"
    echo "   请安装这些工具后再运行迁移脚本"
    exit 1
fi

# psql 是可选的（如果需要从旧数据库迁移）
HAS_PSQL=false
if command -v psql &> /dev/null; then
    HAS_PSQL=true
fi

# 检查后端服务是否就绪
echo -e "${BLUE}1️⃣ 检查后端服务状态...${NC}"

# 先快速检查一次（服务通常已经运行）
if curl -s --max-time 3 "${API_BASE_URL%/api}/actuator/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 后端服务已就绪${NC}"
else
    # 如果第一次检查失败，可能是服务刚启动，短暂等待
    echo "  后端服务可能正在启动，等待中..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    SERVICE_READY=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s --max-time 3 "${API_BASE_URL%/api}/actuator/health" > /dev/null 2>&1; then
            SERVICE_READY=true
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "  等待中... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 2
    done

    if [ "$SERVICE_READY" = false ]; then
        echo -e "${RED}❌ 后端服务未就绪，无法进行数据迁移${NC}"
        echo "   请确保后端服务正在运行: ${API_BASE_URL%/api}/actuator/health"
        exit 1
    fi

    echo -e "${GREEN}✅ 后端服务已就绪${NC}"
fi
echo ""

# 登录获取 token
echo -e "${BLUE}2️⃣ 登录获取认证 token...${NC}"
LOGIN_RESPONSE=$(curl -s -X POST "${API_BASE_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"identityType\":\"EMAIL\",\"identity\":\"${LOGIN_EMAIL}\",\"password\":\"${LOGIN_PASSWORD}\"}" 2>&1)

# 尝试多种可能的 token 字段名
TOKEN=""
if echo "$LOGIN_RESPONSE" | jq -e '.token' > /dev/null 2>&1; then
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token')
elif echo "$LOGIN_RESPONSE" | jq -e '.data.jwt' > /dev/null 2>&1; then
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.jwt')
elif echo "$LOGIN_RESPONSE" | jq -e '.data.token' > /dev/null 2>&1; then
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.token')
fi

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo -e "${GREEN}✅ 登录成功${NC}"
else
    echo -e "${RED}❌ 登录失败${NC}"
    echo "$LOGIN_RESPONSE" | jq '.' 2>/dev/null || echo "$LOGIN_RESPONSE"
    exit 1
fi
echo ""

# 设置认证头
AUTH_HEADER="Authorization: Bearer $TOKEN"
JWT_TOKEN="$TOKEN"

# 检查旧数据库连接
echo -e "${BLUE}3️⃣ 检查旧数据库连接...${NC}"

if [ "$HAS_PSQL" = false ]; then
    echo -e "${YELLOW}⚠️  psql 未安装，将跳过从旧数据库迁移${NC}"
    echo "   提示: 如果需要迁移数据，请安装 psql 工具"
    exit 0
fi

# 尝试设置 Kubernetes port-forward（如果配置了）
SKIP_PORT_FORWARD=false
if [ -n "$KUBECONFIG_PATH" ] && [ -f "$KUBECONFIG_PATH" ]; then
    export KUBECONFIG="$KUBECONFIG_PATH"
    echo "  使用 kubeconfig: $KUBECONFIG_PATH"
    
    if command -v kubectl &> /dev/null; then
        if kubectl cluster-info &> /dev/null 2>&1; then
            echo "  检查 Kubernetes service: $KUBECTL_SERVICE"
            if kubectl get svc "$KUBECTL_SERVICE" &> /dev/null 2>&1; then
                # 检查端口是否已被占用
                if lsof -Pi :$KUBECTL_PORT_FORWARD_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠️  端口 $KUBECTL_PORT_FORWARD_PORT 已被占用，使用现有连接${NC}"
                else
                    echo "  启动 port-forward: $KUBECTL_SERVICE -> localhost:$KUBECTL_PORT_FORWARD_PORT"
                    kubectl port-forward svc/$KUBECTL_SERVICE $KUBECTL_PORT_FORWARD_PORT:5432 > /tmp/port-forward.log 2>&1 &
                    PORT_FORWARD_PID=$!
                    
                    # 等待 port-forward 建立
                    echo "  等待 port-forward 建立..."
                    for i in {1..10}; do
                        if lsof -Pi :$KUBECTL_PORT_FORWARD_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
                            echo -e "${GREEN}✅ Port-forward 已建立 (PID: $PORT_FORWARD_PID)${NC}"
                            OLD_DB_PORT="$KUBECTL_PORT_FORWARD_PORT"
                            break
                        fi
                        if [ $i -eq 10 ]; then
                            echo -e "${YELLOW}⚠️  Port-forward 建立超时，使用直接连接${NC}"
                            SKIP_PORT_FORWARD=true
                        fi
                        sleep 1
                    done
                fi
            else
                echo -e "${YELLOW}⚠️  Service '$KUBECTL_SERVICE' 不存在，使用直接连接${NC}"
                SKIP_PORT_FORWARD=true
            fi
        else
            echo -e "${YELLOW}⚠️  无法连接到 Kubernetes 集群，使用直接连接${NC}"
            SKIP_PORT_FORWARD=true
        fi
    else
        echo -e "${YELLOW}⚠️  kubectl 未安装，使用直接连接${NC}"
        SKIP_PORT_FORWARD=true
    fi
fi

echo "   测试连接: $OLD_DB_USER@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME"
if ! PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  无法连接到旧数据库，跳过数据迁移${NC}"
    echo ""
    echo "   当前配置："
    echo "     OLD_DB_HOST: $OLD_DB_HOST"
    echo "     OLD_DB_PORT: $OLD_DB_PORT"
    echo "     OLD_DB_NAME: $OLD_DB_NAME"
    echo "     OLD_DB_USER: $OLD_DB_USER"
    echo ""
    echo "   提示: 如果需要迁移数据，请确保："
    echo "   1. 旧数据库可通过 Kubernetes port-forward 访问"
    echo "   2. 设置了正确的数据库连接信息（通过环境变量）"
    echo "   3. 数据库服务正在运行"
    exit 0
fi

echo -e "${GREEN}✅ 旧数据库连接成功${NC}"
echo ""

# 创建临时目录和 ID 映射文件
TEMP_DIR=$(mktemp -d)
ID_MAPPING_FILE="${TEMP_DIR}/id_mapping.txt"
touch "$ID_MAPPING_FILE"

# API 调用函数
call_api() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    # 使用超时和连接超时设置
    local response=$(curl -s --max-time 30 --connect-timeout 10 -w "\n%{http_code}" -X "$method" \
        "${API_BASE_URL}${endpoint}" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        ${data:+-d "$data"} 2>&1)
    
    # 检查 curl 是否成功执行
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        echo -e "${RED}API Error: curl 执行失败 (退出码: $curl_exit)${NC}" >&2
        echo "响应: $response" >&2
        return 1
    fi
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    # 处理 HTTP 000 (连接失败)
    if [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
        echo -e "${RED}API Error: 无法连接到后端服务 (HTTP 000)${NC}" >&2
        echo "请检查后端服务是否运行: curl ${API_BASE_URL%/api}/actuator/health" >&2
        return 1
    fi
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$body"
        return 0
    elif [ "$http_code" -eq 400 ]; then
        # Check if it's a "already exists" error - this is OK, we can continue
        if echo "$body" | grep -qi "already exists\|duplicate\|unique"; then
            echo "$body"
            return 2  # Special return code for "already exists"
        else
            echo -e "${YELLOW}API Warning (HTTP $http_code): $body${NC}" >&2
            return 1
        fi
    elif [ "$http_code" -eq 500 ]; then
        # 500 might be "already exists" or other server error
        if echo "$body" | grep -qi "already exists\|duplicate\|unique"; then
            echo "$body"
            return 2  # Treat as "already exists"
        else
            echo -e "${RED}API Error (HTTP $http_code): $body${NC}" >&2
            return 1
        fi
    else
        echo -e "${RED}API Error (HTTP $http_code): $body${NC}" >&2
        return 1
    fi
}

# URL 编码函数（简单版本，处理空格和特殊字符）
url_encode() {
    local string="$1"
    # 使用 awk 或 sed 进行简单的 URL 编码
    echo "$string" | sed 's/ /%20/g; s/&/%26/g; s/#/%23/g; s/\$/%24/g; s/\+/%2B/g; s/,/%2C/g; s/\//%2F/g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g'
}

# 查找已存在的 Broker Group（通过 name 或 abn）
find_existing_broker_group() {
    local name=$1
    local abn=$2
    
    # 尝试通过 ABN 查找（唯一，更快）
    if [ -n "$abn" ] && [ "$abn" != "0" ]; then
        # 对 ABN 进行 URL 编码（移除空格，因为 ABN 通常不应该有空格）
        local abn_clean=$(echo "$abn" | tr -d ' ')
        local abn_encoded=$(url_encode "$abn_clean")
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
    
    # 尝试通过 name 查找（使用超时，避免卡住）
    set +e
    local response=$(timeout 15 bash -c "call_api \"GET\" \"/company?type=BROKER_GROUP\" \"\" 2>/dev/null" 2>/dev/null || echo "")
    local api_exit=$?
    set -e
    
    # 如果 timeout 命令不存在，直接调用（macOS 可能没有 timeout）
    if ! command -v timeout &> /dev/null; then
        set +e
        response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
        api_exit=$?
        set -e
    fi
    
    if [ $api_exit -eq 0 ] && [ -n "$response" ]; then
        # 对 name 进行 JSON 转义
        local name_escaped=$(echo "$name" | sed 's/"/\\"/g')
        local id=$(echo "$response" | jq -r ".data.companies[] | select(.name == \"$name_escaped\") | .id" 2>/dev/null | head -1)
        if [ -n "$id" ] && [ "$id" != "null" ]; then
            echo "$id"
            return 0
        fi
    fi
    
    return 1
}

# 查找已存在的 Broker（通过 email）
find_existing_broker() {
    local email=$1
    
    # URL 编码 email（处理特殊字符如 @）
    local email_encoded=$(echo "$email" | sed 's/@/%40/g; s/ /%20/g')
    
    local response=$(call_api "GET" "/broker?email=${email_encoded}" "")
    local api_result=$?
    
    if [ $api_result -eq 0 ]; then
        # 检查响应中是否有精确匹配的 email
        local brokers_count=$(echo "$response" | jq '.data.brokers | length' 2>/dev/null || echo "0")
        if [ "$brokers_count" -gt 0 ]; then
            # 遍历所有返回的 brokers，找到精确匹配的 email
            local i=0
            while [ $i -lt "$brokers_count" ]; do
                local found_email=$(echo "$response" | jq -r ".data.brokers[$i].email // empty" 2>/dev/null)
                if [ "$found_email" = "$email" ]; then
                    local id=$(echo "$response" | jq -r ".data.brokers[$i].id // empty" 2>/dev/null)
                    if [ -n "$id" ] && [ "$id" != "null" ]; then
                        echo "$id"
                        return 0
                    fi
                fi
                i=$((i + 1))
            done
        fi
    fi
    
    return 1
}

# 迁移 Broker Groups
echo -e "${BLUE}4️⃣ 迁移 Broker Groups...${NC}"

# 检查老系统表结构（可能是 companies 或 broker_group）
BROKER_GROUPS_COUNT=0
BROKER_GROUPS_QUERY=""
if PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM companies WHERE type = 2 AND deleted IS NULL;" > /dev/null 2>&1; then
    BROKER_GROUPS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM companies WHERE type = 2 AND deleted IS NULL;" | tr -d ' ')
    BROKER_GROUPS_QUERY="SELECT id, name, COALESCE(abn::text, ''), COALESCE(account_name, ''), COALESCE(bsb_number::text, ''), COALESCE(account_number::text, ''), COALESCE(email, ''), COALESCE(phone, ''), COALESCE(address, '') FROM companies WHERE type = 2 AND deleted IS NULL ORDER BY id"
elif PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker_group WHERE deleted IS NULL;" > /dev/null 2>&1; then
    BROKER_GROUPS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker_group WHERE deleted IS NULL;" | tr -d ' ')
    BROKER_GROUPS_QUERY="SELECT id, name, COALESCE(abn::text, ''), COALESCE(account_name, ''), COALESCE(bsb_number::text, ''), COALESCE(account_number::text, ''), COALESCE(email, ''), COALESCE(phone, ''), COALESCE(address, '') FROM broker_group WHERE deleted IS NULL ORDER BY id"
fi

if [ "$BROKER_GROUPS_COUNT" -gt 0 ]; then
    echo "   发现 $BROKER_GROUPS_COUNT 个 Broker Groups"
    
    # 导出 Broker Groups
    PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -F"," \
        -c "$BROKER_GROUPS_QUERY" > "${TEMP_DIR}/broker_groups.csv"
    
    IMPORTED_GROUPS=0
    SKIPPED_GROUPS=0
    FAILED_GROUPS=0
    
    while IFS=',' read -r old_id name abn account_name bsb account_number email phone address || [ -n "$old_id" ]; do
        # 使用 set +e 来允许循环中的错误
        set +e
        
        # Trim whitespace（使用 || true 防止失败）
        old_id=$(echo "$old_id" | xargs || echo "")
        name=$(echo "$name" | xargs || echo "")
        abn=$(echo "$abn" | xargs || echo "")
        account_name=$(echo "$account_name" | xargs || echo "")
        bsb=$(echo "$bsb" | xargs || echo "")
        account_number=$(echo "$account_number" | xargs || echo "")
        email=$(echo "$email" | xargs || echo "")
        phone=$(echo "$phone" | xargs || echo "")
        address=$(echo "$address" | xargs || echo "")
        
        # 恢复 set -e
        set -e
        
        # Skip if old_id or name is empty (但确保不会因为空行而退出循环)
        if [ -z "$old_id" ]; then
            # 空行，跳过
            continue
        fi
        
        if [ -z "$name" ]; then
            echo -e "${YELLOW}   ⚠️  跳过空名称的 Broker Group (old ID: $old_id)${NC}"
            set +e
            ((SKIPPED_GROUPS++)) || SKIPPED_GROUPS=$((SKIPPED_GROUPS + 1))
            set -e
            continue
        fi
        
        # 检查是否已存在（忽略错误，继续处理）
        set +e
        existing_id=$(find_existing_broker_group "$name" "$abn" 2>/dev/null || echo "")
        set -e
        
        if [ -n "$existing_id" ]; then
            echo "$old_id:$existing_id" >> "$ID_MAPPING_FILE" 2>/dev/null || true
            echo -e "${GREEN}   ✓ 已存在: $name (new ID: $existing_id)${NC}"
            set +e
            ((IMPORTED_GROUPS++)) || IMPORTED_GROUPS=$((IMPORTED_GROUPS + 1))
            set -e
            continue
        fi
        
        # Clean ABN (remove non-digits)
        abn_clean=$(echo "$abn" | tr -d -c '0-9')
        if [ -z "$abn_clean" ]; then
            abn_clean="1000000000$old_id"
        fi
        
        # Set default values if missing
        if [ -z "$account_name" ]; then
            account_name="${name} Bank Account"
        fi
        
        # Clean BSB and account number
        bsb_clean=$(echo "$bsb" | tr -d -c '0-9')
        if [ -z "$bsb_clean" ]; then
            bsb_clean="123456"
        fi
        
        account_clean=$(echo "$account_number" | tr -d -c '0-9')
        if [ -z "$account_clean" ]; then
            account_clean="12345678"
        fi
        
        # Build JSON payload（使用 set +e 防止失败）
        set +e
        json_payload=$(jq -n \
            --arg name "$name" \
            --arg abn_str "$abn_clean" \
            --arg bank_account_name "$account_name" \
            --arg bsb_str "$bsb_clean" \
            --arg account_str "$account_clean" \
            --arg aggregator_id_str "$AGGREGATOR_COMPANY_ID" \
            --arg email "$email" \
            --arg phone "$phone" \
            --arg address "$address" \
            '{
                name: $name,
                abn: ($abn_str | tonumber),
                bankAccountName: $bank_account_name,
                bankAccountBsb: ($bsb_str | tonumber),
                bankAccountNumber: ($account_str | tonumber),
                aggregatorCompanyId: ($aggregator_id_str | tonumber)
            } + (if $email != "" then {email: $email} else {} end) + 
              (if $phone != "" then {phoneNumber: $phone} else {} end) + 
              (if $address != "" then {address: $address} else {} end)' 2>&1)
        jq_result=$?
        set -e
        
        if [ $jq_result -ne 0 ]; then
            echo -e "${RED}   ✗ JSON 构建失败: $json_payload${NC}"
            set +e
            ((FAILED_GROUPS++)) || FAILED_GROUPS=$((FAILED_GROUPS + 1))
            set -e
            continue
        fi
        
        echo "   导入 Broker Group: $name (old ID: $old_id)..."
        
        # 使用 set +e 允许 API 调用失败
        set +e
        response=$(call_api "POST" "/company/broker-group" "$json_payload" 2>&1)
        api_result=$?
        set -e
        
        if [ $api_result -eq 0 ]; then
            new_id=$(echo "$response" | jq -r '.data.companies[0].id // empty' 2>/dev/null || echo "")
            if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
                echo "$old_id:$new_id" >> "$ID_MAPPING_FILE" || true
                echo -e "${GREEN}   ✓ 导入成功 (new ID: $new_id)${NC}"
                ((IMPORTED_GROUPS++)) || true
            else
                echo -e "${RED}   ✗ 无法从响应中获取新 ID${NC}"
                echo "   响应: $response" | head -3
                ((FAILED_GROUPS++)) || true
            fi
        elif [ $api_result -eq 2 ]; then
            # Already exists - try to find it
            set +e
            existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo "")
            set -e
            if [ -n "$existing_id" ]; then
                echo "$old_id:$existing_id" >> "$ID_MAPPING_FILE" || true
                echo -e "${GREEN}   ✓ 已存在 (new ID: $existing_id)${NC}"
                ((IMPORTED_GROUPS++)) || true
            else
                echo -e "${YELLOW}   ⚠️  已存在但无法找到 ID${NC}"
                ((SKIPPED_GROUPS++)) || true
            fi
        else
            echo -e "${RED}   ✗ 导入失败 (退出码: $api_result)${NC}"
            echo "   响应: $response" | head -3
            ((FAILED_GROUPS++)) || true
        fi
    done < "${TEMP_DIR}/broker_groups.csv"
    
    echo -e "${GREEN}   ✅ Broker Groups 迁移完成: $IMPORTED_GROUPS 成功, $SKIPPED_GROUPS 跳过, $FAILED_GROUPS 失败${NC}"
else
    echo "   未发现需要迁移的 Broker Groups"
fi
echo ""

# 迁移 Brokers
echo -e "${BLUE}5️⃣ 迁移 Brokers...${NC}"

# 首先检查是否需要创建 "Direct Payment Brokers" Broker Group
DIRECT_PAYMENT_GROUP_ID=""
# 先确定表名
BROKERS_TABLE=""
if PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker WHERE deleted IS NULL;" > /dev/null 2>&1; then
    BROKERS_TABLE="broker"
elif PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM brokers WHERE deleted IS NULL;" > /dev/null 2>&1; then
    BROKERS_TABLE="brokers"
fi

DIRECT_PAYMENT_COUNT=0
if [ -n "$BROKERS_TABLE" ]; then
    DIRECT_PAYMENT_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM $BROKERS_TABLE WHERE deleted IS NULL AND (broker_group_id = 0 OR broker_group_id IS NULL OR sub_broker_id IS NOT NULL AND sub_broker_id != 0);" 2>/dev/null | tr -d ' ' || echo "0")
fi

if [ "$DIRECT_PAYMENT_COUNT" -gt 0 ] 2>/dev/null; then
    echo "   发现 $DIRECT_PAYMENT_COUNT 个 DIRECT_PAYMENT brokers，需要创建特殊 Broker Group"
    
    # 检查是否已存在 "Direct Payment Brokers" Broker Group
    # 优先通过 ABN 查找（更快，避免查询所有 broker groups）
    set +e
    DIRECT_PAYMENT_GROUP_ID=$(find_existing_broker_group "Direct Payment Brokers" "1000000000000" 2>/dev/null || echo "")
    set -e
    
    if [ -z "$DIRECT_PAYMENT_GROUP_ID" ]; then
        echo "   创建 'Direct Payment Brokers' Broker Group..."
        direct_payment_json=$(jq -n \
            --arg aggregator_id_str "$AGGREGATOR_COMPANY_ID" \
            '{
                name: "Direct Payment Brokers",
                abn: 1000000000000,
                bankAccountName: "Direct Payment Brokers Bank Account",
                bankAccountBsb: 123456,
                bankAccountNumber: 12345678,
                aggregatorCompanyId: ($aggregator_id_str | tonumber)
            }')
        
        set +e
        response=$(call_api "POST" "/company/broker-group" "$direct_payment_json" 2>&1)
        api_result=$?
        set -e
        
        if [ $api_result -eq 0 ]; then
            DIRECT_PAYMENT_GROUP_ID=$(echo "$response" | jq -r '.data.companies[0].id // empty' 2>/dev/null || echo "")
            if [ -n "$DIRECT_PAYMENT_GROUP_ID" ] && [ "$DIRECT_PAYMENT_GROUP_ID" != "null" ]; then
                echo -e "${GREEN}   ✓ 已创建 'Direct Payment Brokers' Broker Group (ID: $DIRECT_PAYMENT_GROUP_ID)${NC}"
                # 映射 old_id 0 到新 ID
                echo "0:$DIRECT_PAYMENT_GROUP_ID" >> "$ID_MAPPING_FILE" || true
            else
                echo -e "${YELLOW}   ⚠️  创建成功但无法获取 ID，响应: $response${NC}"
            fi
        elif [ $api_result -eq 2 ]; then
            # Already exists - try to find it
            set +e
            DIRECT_PAYMENT_GROUP_ID=$(find_existing_broker_group "Direct Payment Brokers" "1000000000000" 2>/dev/null || echo "")
            set -e
            if [ -n "$DIRECT_PAYMENT_GROUP_ID" ]; then
                echo -e "${GREEN}   ✓ 'Direct Payment Brokers' Broker Group 已存在 (ID: $DIRECT_PAYMENT_GROUP_ID)${NC}"
                echo "0:$DIRECT_PAYMENT_GROUP_ID" >> "$ID_MAPPING_FILE" || true
            else
                echo -e "${YELLOW}   ⚠️  已存在但无法找到 ID${NC}"
            fi
        else
            echo -e "${RED}   ✗ 创建失败 (退出码: $api_result)，响应: $response${NC}"
            echo -e "${YELLOW}   ⚠️  将继续尝试使用已存在的 Direct Payment Brokers Group${NC}"
            set +e
            DIRECT_PAYMENT_GROUP_ID=$(find_existing_broker_group "Direct Payment Brokers" "1000000000000" 2>/dev/null || echo "")
            set -e
            if [ -n "$DIRECT_PAYMENT_GROUP_ID" ]; then
                echo "0:$DIRECT_PAYMENT_GROUP_ID" >> "$ID_MAPPING_FILE" || true
            fi
        fi
    else
        echo -e "${GREEN}   ✓ 'Direct Payment Brokers' Broker Group 已存在 (ID: $DIRECT_PAYMENT_GROUP_ID)${NC}"
        echo "0:$DIRECT_PAYMENT_GROUP_ID" >> "$ID_MAPPING_FILE" || true
    fi
    echo ""
fi

# 迁移 broker 表（NON_DIRECT_PAYMENT）
echo -e "${BLUE}5.1️⃣ 迁移 broker 表 (NON_DIRECT_PAYMENT)...${NC}"

BROKERS_COUNT=0
BROKERS_TABLE=""
if PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0);" > /dev/null 2>&1; then
    BROKERS_TABLE="broker"
    BROKERS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0);" | tr -d ' ')
elif PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM brokers WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0);" > /dev/null 2>&1; then
    BROKERS_TABLE="brokers"
    BROKERS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM brokers WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0);" | tr -d ' ')
fi

if [ "$BROKERS_COUNT" -gt 0 ]; then
    echo "   发现 $BROKERS_COUNT 个 NON_DIRECT_PAYMENT brokers (表: $BROKERS_TABLE)"
    
    # 导出 broker 表数据（不包含 sub_broker_id != 0 的记录）
    PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -F"," \
        -c "SELECT id, COALESCE(name, ''), broker_group_id, COALESCE(infinity_id::text, '') FROM $BROKERS_TABLE WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0) ORDER BY id" > "${TEMP_DIR}/brokers.csv" 2>/dev/null
    
    IMPORTED_BROKERS=0
    SKIPPED_BROKERS=0
    FAILED_BROKERS=0
    
    while IFS=',' read -r old_id name old_broker_group_id infinity_id || [ -n "$old_id" ]; do
        set +e
        
        # Trim whitespace
        old_id=$(echo "$old_id" | xargs || echo "")
        name=$(echo "$name" | xargs || echo "")
        old_broker_group_id=$(echo "$old_broker_group_id" | xargs || echo "")
        infinity_id=$(echo "$infinity_id" | xargs || echo "")
        
        set -e
        
        if [ -z "$old_id" ] || [ -z "$name" ]; then
            continue
        fi
        
        # 从 name 生成 email
        name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
        if [ -z "$name_clean" ]; then
            email="broker_${old_id}@migrated.local"
        else
            email="${name_clean}_${old_id}@migrated.local"
        fi
        
        # 检查是否已存在
        set +e
        existing_id=$(find_existing_broker "$email" 2>/dev/null || echo "")
        set -e
        if [ -n "$existing_id" ]; then
            echo -e "${GREEN}   ✓ 已存在: $email (new ID: $existing_id)${NC}"
            set +e
            ((IMPORTED_BROKERS++)) || IMPORTED_BROKERS=$((IMPORTED_BROKERS + 1))
            set -e
            continue
        fi
        
        # 映射 broker_group_id
        new_broker_group_id=$(grep "^${old_broker_group_id}:" "$ID_MAPPING_FILE" 2>/dev/null | cut -d':' -f2 | head -1)
        
        # 如果映射文件中找不到，尝试查询老系统获取 broker group 名称，然后按名称查找
        if [ -z "$new_broker_group_id" ]; then
            set +e
            old_broker_group_name=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT name FROM broker_group WHERE id = $old_broker_group_id AND deleted IS NULL;" 2>/dev/null | xargs || echo "")
            set -e
            
            if [ -n "$old_broker_group_name" ] && [ "$old_broker_group_name" != "" ]; then
                set +e
                find_response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
                find_result=$?
                set -e
                
                if [ $find_result -eq 0 ]; then
                    found_id=$(echo "$find_response" | jq -r ".data.companies[] | select(.name == \"$old_broker_group_name\") | .id" 2>/dev/null | head -1)
                    if [ -n "$found_id" ] && [ "$found_id" != "null" ]; then
                        new_broker_group_id="$found_id"
                    fi
                fi
            fi
            
            # 如果按名称也找不到，尝试直接使用 old_broker_group_id（可能 ID 没有变化）
            if [ -z "$new_broker_group_id" ]; then
                set +e
                check_response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
                check_result=$?
                set -e
                
                if [ $check_result -eq 0 ]; then
                    check_id=$(echo "$check_response" | jq -r ".data.companies[] | select(.id == $old_broker_group_id) | .id" 2>/dev/null | head -1)
                    if [ -n "$check_id" ] && [ "$check_id" != "null" ] && [ "$check_id" = "$old_broker_group_id" ]; then
                        new_broker_group_id="$old_broker_group_id"
                    fi
                fi
            fi
        fi
        
        if [ -z "$new_broker_group_id" ]; then
            echo -e "${YELLOW}   ⚠️  跳过 Broker (old ID: $old_id): Broker Group ID $old_broker_group_id 未找到${NC}"
            set +e
            ((SKIPPED_BROKERS++)) || SKIPPED_BROKERS=$((SKIPPED_BROKERS + 1))
            set -e
            continue
        fi
        
        # 生成 CRN（老系统没有 CRN，使用假的 CRN "123" + 后缀确保唯一性）
        crn="123_${old_id}"
        
        # Build JSON payload
        json_payload=$(jq -n \
            --arg email "$email" \
            --arg type "NON_DIRECT_PAYMENT" \
            --arg crn "$crn" \
            --argjson broker_group_id "$new_broker_group_id" \
            --arg infinity_id_str "$infinity_id" \
            '{
                email: $email,
                type: $type,
                crn: $crn,
                brokerGroupId: $broker_group_id
            } + (if $infinity_id_str != "" and $infinity_id_str != "0" and $infinity_id_str != "NULL" then {infinityId: ($infinity_id_str | tonumber)} else {} end)')
        
        echo "   导入 Broker: $email (old ID: $old_id, type: NON_DIRECT_PAYMENT)..."
        
        set +e
        response=$(call_api "POST" "/broker" "$json_payload" 2>&1)
        api_result=$?
        set -e
        
        if [ $api_result -eq 0 ]; then
            new_id=$(echo "$response" | jq -r '.data.brokers[0].id // empty' 2>/dev/null || echo "")
            if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
                echo -e "${GREEN}   ✓ 导入成功 (new ID: $new_id)${NC}"
                set +e
                ((IMPORTED_BROKERS++)) || IMPORTED_BROKERS=$((IMPORTED_BROKERS + 1))
                set -e
            else
                echo -e "${RED}   ✗ 无法从响应中获取新 ID${NC}"
                echo "   响应: $response" | head -3
                set +e
                ((FAILED_BROKERS++)) || FAILED_BROKERS=$((FAILED_BROKERS + 1))
                set -e
            fi
        elif [ $api_result -eq 2 ]; then
            set +e
            existing_id=$(find_existing_broker "$email" 2>/dev/null || echo "")
            set -e
            if [ -n "$existing_id" ]; then
                echo -e "${GREEN}   ✓ 已存在 (new ID: $existing_id)${NC}"
                set +e
                ((IMPORTED_BROKERS++)) || IMPORTED_BROKERS=$((IMPORTED_BROKERS + 1))
                set -e
            else
                echo -e "${YELLOW}   ⚠️  已存在但无法找到 ID${NC}"
                set +e
                ((SKIPPED_BROKERS++)) || SKIPPED_BROKERS=$((SKIPPED_BROKERS + 1))
                set -e
            fi
        else
            echo -e "${RED}   ✗ 导入失败 (退出码: $api_result)${NC}"
            echo "   响应: $response" | head -3
            set +e
            ((FAILED_BROKERS++)) || FAILED_BROKERS=$((FAILED_BROKERS + 1))
            set -e
        fi
    done < "${TEMP_DIR}/brokers.csv"
    
    echo -e "${GREEN}   ✅ NON_DIRECT_PAYMENT Brokers 迁移完成: $IMPORTED_BROKERS 成功, $SKIPPED_BROKERS 跳过, $FAILED_BROKERS 失败${NC}"
else
    echo "   未发现需要迁移的 NON_DIRECT_PAYMENT Brokers"
fi
echo ""

# 迁移 sub_broker 表（DIRECT_PAYMENT）
echo -e "${BLUE}5.2️⃣ 迁移 sub_broker 表 (DIRECT_PAYMENT)...${NC}"

SUB_BROKERS_COUNT=0
if PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM sub_broker WHERE deleted IS NULL;" > /dev/null 2>&1; then
    SUB_BROKERS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM sub_broker WHERE deleted IS NULL;" | tr -d ' ')
fi

if [ "$SUB_BROKERS_COUNT" -gt 0 ]; then
    echo "   发现 $SUB_BROKERS_COUNT 个 DIRECT_PAYMENT brokers (表: sub_broker)"
    
    # 导出 sub_broker 表数据（包含所有字段，bsb_number 和 account_number 作为直接字段）
    PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -F"," \
        -c "SELECT id, COALESCE(email, ''), COALESCE(name, ''), broker_group_id, COALESCE(infinity_id::text, ''), COALESCE(bsb_number, ''), COALESCE(account_number, ''), COALESCE(abn, ''), COALESCE(address, ''), COALESCE(phone, ''), COALESCE(deduct::text, 'false'), COALESCE(account_name, '') FROM sub_broker WHERE deleted IS NULL ORDER BY id" > "${TEMP_DIR}/sub_brokers.csv" 2>/dev/null
    
    IMPORTED_SUB_BROKERS=0
    SKIPPED_SUB_BROKERS=0
    FAILED_SUB_BROKERS=0
    
    while IFS=',' read -r old_id email name broker_group_id infinity_id bsb_number account_number abn address phone deduct account_name || [ -n "$old_id" ]; do
        set +e
        
        # Trim whitespace
        old_id=$(echo "$old_id" | xargs || echo "")
        email=$(echo "$email" | xargs || echo "")
        name=$(echo "$name" | xargs || echo "")
        broker_group_id=$(echo "$broker_group_id" | xargs || echo "")
        infinity_id=$(echo "$infinity_id" | xargs || echo "")
        bsb_number=$(echo "$bsb_number" | xargs || echo "")
        account_number=$(echo "$account_number" | xargs || echo "")
        abn=$(echo "$abn" | xargs || echo "")
        address=$(echo "$address" | xargs || echo "")
        phone=$(echo "$phone" | xargs || echo "")
        deduct=$(echo "$deduct" | xargs || echo "")
        account_name=$(echo "$account_name" | xargs || echo "")
        
        set -e
        
        if [ -z "$old_id" ]; then
            continue
        fi
        
        # 处理 email：如果为空，从 name 生成
        if [ -z "$email" ] || [ "$email" = "" ]; then
            name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
            if [ -z "$name_clean" ]; then
                email="sub_broker_${old_id}@migrated.local"
            else
                email="${name_clean}_${old_id}@migrated.local"
            fi
        fi
        
        # 检查是否已存在
        set +e
        existing_id=$(find_existing_broker "$email" 2>/dev/null || echo "")
        set -e
        if [ -n "$existing_id" ]; then
            echo -e "${GREEN}   ✓ 已存在: $email (new ID: $existing_id)${NC}"
            set +e
            ((IMPORTED_SUB_BROKERS++)) || IMPORTED_SUB_BROKERS=$((IMPORTED_SUB_BROKERS + 1))
            set -e
            continue
        fi
        
        # 映射 broker_group_id
        new_broker_group_id=$(grep "^${broker_group_id}:" "$ID_MAPPING_FILE" 2>/dev/null | cut -d':' -f2 | head -1)
        
        # 如果映射文件中找不到，尝试查询老系统获取 broker group 名称，然后按名称查找
        if [ -z "$new_broker_group_id" ]; then
            set +e
            old_broker_group_name=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT name FROM broker_group WHERE id = $broker_group_id AND deleted IS NULL;" 2>/dev/null | xargs || echo "")
            set -e
            
            if [ -n "$old_broker_group_name" ] && [ "$old_broker_group_name" != "" ]; then
                set +e
                find_response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
                find_result=$?
                set -e
                
                if [ $find_result -eq 0 ]; then
                    found_id=$(echo "$find_response" | jq -r ".data.companies[] | select(.name == \"$old_broker_group_name\") | .id" 2>/dev/null | head -1)
                    if [ -n "$found_id" ] && [ "$found_id" != "null" ]; then
                        new_broker_group_id="$found_id"
                    fi
                fi
            fi
            
            # 如果按名称也找不到，尝试直接使用 broker_group_id（可能 ID 没有变化）
            if [ -z "$new_broker_group_id" ]; then
                set +e
                check_response=$(call_api "GET" "/company?type=BROKER_GROUP" "" 2>/dev/null)
                check_result=$?
                set -e
                
                if [ $check_result -eq 0 ]; then
                    check_id=$(echo "$check_response" | jq -r ".data.companies[] | select(.id == $broker_group_id) | .id" 2>/dev/null | head -1)
                    if [ -n "$check_id" ] && [ "$check_id" != "null" ] && [ "$check_id" = "$broker_group_id" ]; then
                        new_broker_group_id="$broker_group_id"
                    fi
                fi
            fi
        fi
        
        if [ -z "$new_broker_group_id" ]; then
            echo -e "${YELLOW}   ⚠️  跳过 Sub Broker (old ID: $old_id): Broker Group ID $broker_group_id 未找到${NC}"
            set +e
            ((SKIPPED_SUB_BROKERS++)) || SKIPPED_SUB_BROKERS=$((SKIPPED_SUB_BROKERS + 1))
            set -e
            continue
        fi
        
        # 生成 CRN（老系统没有 CRN，使用假的 CRN "123" + 后缀确保唯一性）
        crn="123_SUB_${old_id}"
        
        # 清理 BSB 和 account number（移除非数字字符）
        bsb_clean=$(echo "$bsb_number" | tr -d -c '0-9')
        account_clean=$(echo "$account_number" | tr -d -c '0-9')
        
        # 构建 extra_info JSON（不包含 abn，只包含 address, phone, deduct, account_name）
        # 注意：bsb_number 和 account_number 现在直接作为字段，不再放入 extra_info
        # 注意：abn 不迁移（按照用户要求）
        extra_info_json=$(jq -n \
            --arg address "$address" \
            --arg phone "$phone" \
            --arg deduct "$deduct" \
            --arg account_name "$account_name" \
            '{} + 
            (if $address != "" and $address != "NULL" then {address: $address} else {} end) +
            (if $phone != "" and $phone != "NULL" then {phone: $phone} else {} end) +
            (if $deduct != "" and $deduct != "NULL" and $deduct != "false" then {deduct: ($deduct == "true" or $deduct == "t")} else {} end) +
            (if $account_name != "" and $account_name != "NULL" then {accountName: $account_name} else {} end)')
        
        # Build JSON payload
        json_payload=$(jq -n \
            --arg email "$email" \
            --arg type "DIRECT_PAYMENT" \
            --arg crn "$crn" \
            --argjson broker_group_id "$new_broker_group_id" \
            --arg infinity_id_str "$infinity_id" \
            --arg bsb_str "$bsb_clean" \
            --arg account_str "$account_clean" \
            --argjson extra_info "$extra_info_json" \
            '{
                email: $email,
                type: $type,
                crn: $crn,
                brokerGroupId: $broker_group_id
            } + (if $infinity_id_str != "" and $infinity_id_str != "0" and $infinity_id_str != "NULL" then {infinityId: ($infinity_id_str | tonumber)} else {} end) +
              (if $bsb_str != "" then {bankAccountBsb: ($bsb_str | tonumber)} else {} end) +
              (if $account_str != "" then {bankAccountNumber: ($account_str | tonumber)} else {} end) +
              (if ($extra_info | length) > 0 then {extraInfo: $extra_info} else {} end)')
        
        echo "   导入 Sub Broker: $email (old ID: $old_id, type: DIRECT_PAYMENT)..."
        
        set +e
        response=$(call_api "POST" "/broker" "$json_payload" 2>&1)
        api_result=$?
        set -e
        
        if [ $api_result -eq 0 ]; then
            new_id=$(echo "$response" | jq -r '.data.brokers[0].id // empty' 2>/dev/null || echo "")
            if [ -n "$new_id" ] && [ "$new_id" != "null" ]; then
                echo -e "${GREEN}   ✓ 导入成功 (new ID: $new_id)${NC}"
                set +e
                ((IMPORTED_SUB_BROKERS++)) || IMPORTED_SUB_BROKERS=$((IMPORTED_SUB_BROKERS + 1))
                set -e
            else
                echo -e "${RED}   ✗ 无法从响应中获取新 ID${NC}"
                echo "   响应: $response" | head -3
                set +e
                ((FAILED_SUB_BROKERS++)) || FAILED_SUB_BROKERS=$((FAILED_SUB_BROKERS + 1))
                set -e
            fi
        elif [ $api_result -eq 2 ]; then
            set +e
            existing_id=$(find_existing_broker "$email" 2>/dev/null || echo "")
            set -e
            if [ -n "$existing_id" ]; then
                echo -e "${GREEN}   ✓ 已存在 (new ID: $existing_id)${NC}"
                set +e
                ((IMPORTED_SUB_BROKERS++)) || IMPORTED_SUB_BROKERS=$((IMPORTED_SUB_BROKERS + 1))
                set -e
            else
                echo -e "${YELLOW}   ⚠️  已存在但无法找到 ID${NC}"
                set +e
                ((SKIPPED_SUB_BROKERS++)) || SKIPPED_SUB_BROKERS=$((SKIPPED_SUB_BROKERS + 1))
                set -e
            fi
        else
            echo -e "${RED}   ✗ 导入失败 (退出码: $api_result)${NC}"
            echo "   响应: $response" | head -3
            set +e
            ((FAILED_SUB_BROKERS++)) || FAILED_SUB_BROKERS=$((FAILED_SUB_BROKERS + 1))
            set -e
        fi
    done < "${TEMP_DIR}/sub_brokers.csv"
    
    echo -e "${GREEN}   ✅ DIRECT_PAYMENT Brokers 迁移完成: $IMPORTED_SUB_BROKERS 成功, $SKIPPED_SUB_BROKERS 跳过, $FAILED_SUB_BROKERS 失败${NC}"
else
    echo "   未发现需要迁移的 DIRECT_PAYMENT Brokers (sub_broker 表)"
fi
echo ""

# 迁移 Fee Models
echo -e "${BLUE}6️⃣ 迁移 Fee Models...${NC}"
FEE_MODELS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM fee_models WHERE deleted IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$FEE_MODELS_COUNT" -gt 0 ] 2>/dev/null; then
    echo "   发现 $FEE_MODELS_COUNT 个 Fee Models"
    echo -e "${YELLOW}   ⚠️  Fee Models 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Fee Models"
fi
echo ""

# 迁移 Commission Models
echo -e "${BLUE}7️⃣ 迁移 Commission Models...${NC}"
COMMISSION_MODELS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM commission_models WHERE deleted IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$COMMISSION_MODELS_COUNT" -gt 0 ] 2>/dev/null; then
    echo "   发现 $COMMISSION_MODELS_COUNT 个 Commission Models"
    echo -e "${YELLOW}   ⚠️  Commission Models 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Commission Models"
fi
echo ""

# 清理临时文件
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✅ 数据迁移完成${NC}"
echo ""
echo -e "${BLUE}📊 迁移摘要:${NC}"
echo "   - Broker Groups: 已迁移"
echo "   - Brokers (NON_DIRECT_PAYMENT): 已迁移"
echo "   - Sub Brokers (DIRECT_PAYMENT): 已迁移"
echo "   - Fee Models: 待实现（可选）"
echo "   - Commission Models: 待实现（可选）"

