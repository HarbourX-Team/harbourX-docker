#!/bin/bash

# 数据迁移脚本 - 从旧 HaiMoney 系统迁移数据到新 HarbourX 系统
# 此脚本会在 deploy backend 后自动运行

set -e

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

# 旧系统数据库配置（通过 Kubernetes port-forward）
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_NAME="${OLD_DB_NAME:-haimoney}"
OLD_DB_USER="${OLD_DB_USER:-postgres}"
OLD_DB_PASS="${OLD_DB_PASS:-postgres}"

# 跳过迁移标志
SKIP_MIGRATION="${SKIP_MIGRATION:-false}"

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
for tool in psql curl jq; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}❌ 缺少必需工具:${MISSING_TOOLS}${NC}"
    echo "   请安装这些工具后再运行迁移脚本"
    exit 1
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

if echo "$LOGIN_RESPONSE" | jq -e '.token' > /dev/null 2>&1; then
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token')
    echo -e "${GREEN}✅ 登录成功${NC}"
else
    echo -e "${RED}❌ 登录失败${NC}"
    echo "$LOGIN_RESPONSE" | jq '.' 2>/dev/null || echo "$LOGIN_RESPONSE"
    exit 1
fi
echo ""

# 设置认证头
AUTH_HEADER="Authorization: Bearer $TOKEN"

# 检查旧数据库连接
echo -e "${BLUE}3️⃣ 检查旧数据库连接...${NC}"
if ! PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  无法连接到旧数据库，跳过数据迁移${NC}"
    echo "   提示: 如果需要迁移数据，请确保："
    echo "   1. 旧数据库可通过 Kubernetes port-forward 访问"
    echo "   2. 设置了正确的数据库连接信息"
    exit 0
fi

echo -e "${GREEN}✅ 旧数据库连接成功${NC}"
echo ""

# 迁移 Broker Groups
echo -e "${BLUE}4️⃣ 迁移 Broker Groups...${NC}"
BROKER_GROUPS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM companies WHERE type = 2;" | tr -d ' ')

if [ "$BROKER_GROUPS_COUNT" -gt 0 ]; then
    echo "   发现 $BROKER_GROUPS_COUNT 个 Broker Groups"
    # TODO: 实现 Broker Groups 迁移逻辑
    echo -e "${YELLOW}   ⚠️  Broker Groups 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Broker Groups"
fi
echo ""

# 迁移 Brokers
echo -e "${BLUE}5️⃣ 迁移 Brokers...${NC}"
BROKERS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM brokers;" | tr -d ' ')

if [ "$BROKERS_COUNT" -gt 0 ]; then
    echo "   发现 $BROKERS_COUNT 个 Brokers"
    # TODO: 实现 Brokers 迁移逻辑
    echo -e "${YELLOW}   ⚠️  Brokers 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Brokers"
fi
echo ""

# 迁移 Fee Models
echo -e "${BLUE}6️⃣ 迁移 Fee Models...${NC}"
FEE_MODELS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM fee_models;" | tr -d ' ')

if [ "$FEE_MODELS_COUNT" -gt 0 ]; then
    echo "   发现 $FEE_MODELS_COUNT 个 Fee Models"
    # TODO: 实现 Fee Models 迁移逻辑
    echo -e "${YELLOW}   ⚠️  Fee Models 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Fee Models"
fi
echo ""

# 迁移 Commission Models
echo -e "${BLUE}7️⃣ 迁移 Commission Models...${NC}"
COMMISSION_MODELS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM commission_models;" | tr -d ' ')

if [ "$COMMISSION_MODELS_COUNT" -gt 0 ]; then
    echo "   发现 $COMMISSION_MODELS_COUNT 个 Commission Models"
    # TODO: 实现 Commission Models 迁移逻辑
    echo -e "${YELLOW}   ⚠️  Commission Models 迁移逻辑待实现${NC}"
else
    echo "   未发现需要迁移的 Commission Models"
fi
echo ""

echo -e "${GREEN}✅ 数据迁移检查完成${NC}"
echo ""
echo -e "${YELLOW}⚠️  注意: 迁移逻辑需要根据具体需求实现${NC}"
echo "   当前脚本仅检查数据源和连接，实际迁移逻辑需要补充"

