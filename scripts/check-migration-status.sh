#!/bin/bash

# 检查数据迁移状态的诊断脚本

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 数据迁移状态诊断${NC}"
echo -e "${BLUE}==================${NC}"
echo ""

# 1. 检查迁移进程
echo -e "${BLUE}1️⃣ 检查迁移进程状态...${NC}"
MIGRATION_PID=$(ps aux | grep -v grep | grep "migrate-data.sh" | awk '{print $2}' | head -1)
if [ -n "$MIGRATION_PID" ]; then
    echo -e "${GREEN}✅ 迁移进程正在运行 (PID: $MIGRATION_PID)${NC}"
else
    echo -e "${YELLOW}ℹ️  迁移进程未在运行（可能已完成或未启动）${NC}"
fi
echo ""

# 2. 检查迁移日志
echo -e "${BLUE}2️⃣ 检查迁移日志...${NC}"
if [ -f /tmp/migration.log ]; then
    LOG_SIZE=$(wc -l < /tmp/migration.log | tr -d ' ')
    echo "  日志文件存在，共 $LOG_SIZE 行"
    echo ""
    echo -e "${YELLOW}最后 30 行日志：${NC}"
    echo "  ----------------------------------------"
    tail -30 /tmp/migration.log | sed 's/^/  /'
    echo "  ----------------------------------------"
else
    echo -e "${RED}❌ 迁移日志文件不存在: /tmp/migration.log${NC}"
fi
echo ""

# 3. 检查后端服务状态
echo -e "${BLUE}3️⃣ 检查后端服务状态...${NC}"
API_BASE_URL="${API_BASE_URL:-http://localhost:8080/api}"
if curl -s --max-time 3 "${API_BASE_URL%/api}/actuator/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 后端服务运行正常${NC}"
else
    echo -e "${RED}❌ 后端服务不可访问${NC}"
fi
echo ""

# 4. 检查已迁移的数据
echo -e "${BLUE}4️⃣ 检查已迁移的数据...${NC}"

# 尝试获取 token（如果可能）
LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"

LOGIN_RESPONSE=$(curl -s -X POST "${API_BASE_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"identityType\":\"EMAIL\",\"identity\":\"${LOGIN_EMAIL}\",\"password\":\"${LOGIN_PASSWORD}\"}" 2>&1)

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
    
    # 检查 Broker Groups
    BROKER_GROUPS_RESPONSE=$(curl -s -X GET "${API_BASE_URL}/company?type=BROKER_GROUP" \
        -H "Authorization: Bearer $TOKEN" 2>&1)
    
    if echo "$BROKER_GROUPS_RESPONSE" | jq -e '.data.companies' > /dev/null 2>&1; then
        BROKER_GROUPS_COUNT=$(echo "$BROKER_GROUPS_RESPONSE" | jq '.data.companies | length' 2>/dev/null || echo "0")
        echo "  Broker Groups: $BROKER_GROUPS_COUNT 个"
    else
        echo "  Broker Groups: 无法获取（可能 API 响应格式不同）"
    fi
    
    # 检查 Brokers
    BROKERS_RESPONSE=$(curl -s -X GET "${API_BASE_URL}/broker" \
        -H "Authorization: Bearer $TOKEN" 2>&1)
    
    if echo "$BROKERS_RESPONSE" | jq -e '.data.brokers' > /dev/null 2>&1; then
        BROKERS_COUNT=$(echo "$BROKERS_RESPONSE" | jq '.data.brokers | length' 2>/dev/null || echo "0")
        echo "  Brokers: $BROKERS_COUNT 个"
    else
        echo "  Brokers: 无法获取（可能 API 响应格式不同）"
    fi
else
    echo -e "${YELLOW}⚠️  无法登录，跳过数据检查${NC}"
fi
echo ""

# 5. 检查旧数据库连接配置
echo -e "${BLUE}5️⃣ 检查旧数据库连接配置...${NC}"
OLD_DB_HOST="${OLD_DB_HOST:-localhost}"
OLD_DB_PORT="${OLD_DB_PORT:-5432}"
OLD_DB_NAME="${OLD_DB_NAME:-haimoney}"
OLD_DB_USER="${OLD_DB_USER:-postgres}"
OLD_DB_PASS="${OLD_DB_PASS:-postgres}"

echo "  OLD_DB_HOST: $OLD_DB_HOST"
echo "  OLD_DB_PORT: $OLD_DB_PORT"
echo "  OLD_DB_NAME: $OLD_DB_NAME"
echo "  OLD_DB_USER: $OLD_DB_USER"
echo "  OLD_DB_PASS: ${OLD_DB_PASS:+已设置}"

if command -v psql &> /dev/null; then
    echo ""
    echo "  测试数据库连接..."
    if PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ 旧数据库连接成功${NC}"
        
        # 检查数据量
        BROKER_GROUPS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM companies WHERE type = 2 AND deleted IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$BROKER_GROUPS_COUNT" = "0" ]; then
            # 尝试另一个表名
            BROKER_GROUPS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM broker_group WHERE deleted IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")
        fi
        
        BROKERS_COUNT=$(PGPASSWORD="$OLD_DB_PASS" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -c "SELECT COUNT(*) FROM brokers WHERE deleted IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")
        
        echo "  旧系统中的数据："
        echo "    Broker Groups: $BROKER_GROUPS_COUNT 个"
        echo "    Brokers: $BROKERS_COUNT 个"
    else
        echo -e "${RED}  ❌ 旧数据库连接失败${NC}"
        echo "  可能的原因："
        echo "    - 数据库主机/端口不正确"
        echo "    - 用户名/密码不正确"
        echo "    - 数据库不存在"
        echo "    - 网络连接问题"
        echo "    - 需要 Kubernetes port-forward"
    fi
else
    echo -e "${YELLOW}  ⚠️  psql 未安装，无法测试数据库连接${NC}"
fi
echo ""

# 6. 总结和建议
echo -e "${BLUE}6️⃣ 诊断总结${NC}"
echo ""

if [ -f /tmp/migration.log ]; then
    # 检查日志中的关键信息
    if grep -q "无法连接到旧数据库" /tmp/migration.log; then
        echo -e "${RED}❌ 问题：无法连接到旧数据库${NC}"
        echo ""
        echo "解决方案："
        echo "  1. 检查 OLD_DB_HOST, OLD_DB_PORT, OLD_DB_NAME 等环境变量"
        echo "  2. 如果使用 Kubernetes port-forward，确保已启动："
        echo "     kubectl port-forward svc/<service-name> 5432:5432"
        echo "  3. 测试数据库连接："
        echo "     psql -h \$OLD_DB_HOST -p \$OLD_DB_PORT -U \$OLD_DB_USER -d \$OLD_DB_NAME"
    elif grep -q "未发现需要迁移" /tmp/migration.log; then
        echo -e "${YELLOW}⚠️  问题：旧数据库中没有需要迁移的数据${NC}"
        echo ""
        echo "可能的原因："
        echo "  - 旧数据库中没有 Broker Groups 或 Brokers"
        echo "  - 所有数据都已被标记为删除 (deleted IS NOT NULL)"
    elif grep -q "✅ 数据迁移完成" /tmp/migration.log; then
        echo -e "${GREEN}✅ 迁移脚本已成功完成${NC}"
        echo ""
        echo "请检查上面的数据统计，确认数据是否已迁移。"
    elif grep -q "❌\|错误\|Error\|error" /tmp/migration.log; then
        echo -e "${RED}❌ 迁移过程中出现错误${NC}"
        echo ""
        echo "请查看上面的日志详情，查找错误信息。"
    else
        echo -e "${YELLOW}ℹ️  迁移状态不明确${NC}"
        echo ""
        echo "建议："
        echo "  1. 查看完整日志: tail -100 /tmp/migration.log"
        echo "  2. 检查迁移脚本是否还在运行"
        echo "  3. 手动运行迁移脚本查看详细输出"
    fi
else
    echo -e "${YELLOW}⚠️  迁移日志文件不存在${NC}"
    echo ""
    echo "可能的原因："
    echo "  - 迁移脚本尚未运行"
    echo "  - 迁移脚本运行失败，未生成日志"
fi

echo ""
echo -e "${BLUE}📝 建议的下一步操作：${NC}"
echo "  1. 查看完整日志: tail -100 /tmp/migration.log"
echo "  2. 如果迁移失败，手动运行: /opt/harbourx/migrate-data.sh"
echo "  3. 检查环境变量是否正确设置"
echo "  4. 确认旧数据库可以访问"


