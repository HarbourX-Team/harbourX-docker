#!/bin/bash

# 完整数据迁移脚本
# 按照 MIGRATION_GUIDE.md 规则迁移所有数据
# 迁移顺序：1. (可选) 清理云端数据, 2. Broker Groups, 3. Brokers
#
# 使用方法:
#   ./migrate-all.sh              # 正常迁移
#   ./migrate-all.sh --clean      # 先清理云端数据，再迁移
#   ./migrate-all.sh --clean-only # 仅清理云端数据，不迁移

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$SCRIPT_DIR/migrate-all-${TIMESTAMP}.log"

# 日志函数（必须先定义，因为后面会使用）
log_info() {
    echo_info "$1" | tee -a "$LOG_FILE"
}

log_success() {
    echo_success "$1" | tee -a "$LOG_FILE"
}

log_error() {
    echo_error "$1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo_warn "$1" | tee -a "$LOG_FILE"
}

# 解析命令行参数
CLEAN_BEFORE_MIGRATE=false
CLEAN_ONLY=false

for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BEFORE_MIGRATE=true
            shift
            ;;
        --clean-only)
            CLEAN_ONLY=true
            shift
            ;;
        *)
            echo_warn "未知参数: $arg"
            echo "使用方法: $0 [--clean|--clean-only]"
            exit 1
            ;;
    esac
done

# 环境选择：staging 或 production
ENVIRONMENT="${ENVIRONMENT:-staging}"
if [ "$ENVIRONMENT" = "production" ] || [ "$ENVIRONMENT" = "prod" ]; then
    export ENVIRONMENT="production"
    log_info "使用生产环境 (production)"
else
    export ENVIRONMENT="staging"
    log_info "使用测试环境 (staging)"
fi

log_info "=========================================="
log_info "  完整数据迁移脚本"
log_info "  根据 MIGRATION_GUIDE.md"
log_info "  日志文件: $LOG_FILE"
log_info "=========================================="
echo ""

# 尝试从 haimoney/start_env.sh 加载配置
HAIMONEY_ENV_FILE="${HAIMONEY_ENV_FILE:-../haimoney/start_env.sh}"
if [ -f "$HAIMONEY_ENV_FILE" ]; then
    log_info "从 $HAIMONEY_ENV_FILE 加载配置..."
    set -a
    source "$HAIMONEY_ENV_FILE" 2>/dev/null || true
    set +a
    
    # 从 haimoney 配置中读取数据库信息
    if [ -n "$DB_PW" ]; then
        export OLD_DB_PASS="${OLD_DB_PASS:-$DB_PW}"
        log_success "已从 haimoney 配置加载数据库密码"
    fi
fi

# 检查必需的环境变量
if [ -z "$OLD_DB_PASS" ]; then
    log_warn "OLD_DB_PASS 未设置，尝试从 Kubernetes secret 获取..."
    
    # 尝试从 Kubernetes secret 获取密码
    if command -v kubectl >/dev/null 2>&1; then
        # 尝试多个可能的 secret 名称
        for secret_name in postgres postgresql haimoney-postgres haimoney-db; do
            for namespace in haimoney default staging production; do
                set +e
                DB_PASS=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
                set -e
                if [ -n "$DB_PASS" ]; then
                    export OLD_DB_PASS="$DB_PASS"
                    log_success "从 Kubernetes secret ($namespace/$secret_name) 获取到密码"
                    break 2
                fi
            done
        done
    fi
    
    # 如果仍然没有密码，提示用户（但不退出，让子脚本处理）
    if [ -z "$OLD_DB_PASS" ]; then
        log_warn "OLD_DB_PASS 未设置，子脚本将尝试从 haimoney/start_env.sh 加载"
    fi
fi

# 确定映射文件
if [[ "${API_BASE_URL:-http://13.54.207.94/api}" == *"localhost"* ]] || [[ "${API_BASE_URL:-http://13.54.207.94/api}" == *"127.0.0.1"* ]]; then
    MAPPING_FILE="id_mapping_local.txt"
else
    MAPPING_FILE="id_mapping.txt"
fi

log_info "使用映射文件: $MAPPING_FILE"
log_info "API 地址: ${API_BASE_URL:-http://13.54.207.94/api}"
echo ""

# 清理云端数据函数
clean_cloud_data() {
    log_warn "=========================================="
    log_warn "  清理云端所有数据"
    log_warn "  API: ${API_BASE_URL:-http://13.54.207.94/api}"
    log_warn "=========================================="
    echo ""
    log_warn "⚠️  警告: 此操作将删除云端所有 Broker Groups 和 Brokers！"
    echo ""
    
    # 如果设置了 FORCE_DELETE 环境变量，跳过确认
    if [ "$FORCE_DELETE" != "true" ]; then
        read -p "确认要继续吗？(输入 'YES' 继续): " confirm
        if [ "$confirm" != "YES" ]; then
            log_info "操作已取消"
            return 1
        fi
    else
        log_info "FORCE_DELETE=true，跳过确认，直接删除"
    fi
    
    # 获取认证 token
    log_info "获取认证 token..."
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
        log_error "登录失败，无法获取 token"
        echo "响应: $LOGIN_RESPONSE"
        return 1
    fi
    
    log_success "登录成功"
    
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
    log_info "步骤 1: 删除所有 Brokers..."
    BROKERS_RESPONSE=$(call_api "GET" "/broker" "")
    BROKER_IDS=$(echo "$BROKERS_RESPONSE" | jq -r '.data.brokers[]?.id // .data.brokers[].id // empty' 2>/dev/null)
    
    BROKER_COUNT=0
    BROKER_SUCCESS=0
    BROKER_FAILED=0
    
    if [ -n "$BROKER_IDS" ]; then
        BROKER_COUNT=$(echo "$BROKER_IDS" | wc -l | tr -d ' ')
        log_info "找到 $BROKER_COUNT 个 Brokers"
        
        for broker_id in $BROKER_IDS; do
            if [ -z "$broker_id" ] || [ "$broker_id" = "null" ]; then
                continue
            fi
            
            log_info "删除 Broker ID: $broker_id"
            DELETE_RESPONSE=$(call_api "DELETE" "/broker/$broker_id" "")
            DELETE_CODE=$(echo "$DELETE_RESPONSE" | jq -r '.code // empty' 2>/dev/null)
            
            if [ "$DELETE_CODE" = "0" ] || [ -z "$DELETE_CODE" ]; then
                log_success "  ✅ Broker ID $broker_id 已删除"
                ((BROKER_SUCCESS++))
            else
                log_error "  ❌ Broker ID $broker_id 删除失败: $DELETE_RESPONSE"
                ((BROKER_FAILED++))
            fi
        done
    else
        log_info "未找到任何 Brokers"
    fi
    
    echo ""
    log_info "Brokers 删除完成: 成功=$BROKER_SUCCESS, 失败=$BROKER_FAILED"
    
    # 删除所有 Broker Groups
    echo ""
    log_info "步骤 2: 删除所有 Broker Groups..."
    COMPANIES_RESPONSE=$(call_api "GET" "/company?type=BROKER_GROUP" "")
    COMPANY_IDS=$(echo "$COMPANIES_RESPONSE" | jq -r '.data.companies[]?.id // .data.companies[].id // empty' 2>/dev/null)
    
    COMPANY_COUNT=0
    COMPANY_SUCCESS=0
    COMPANY_FAILED=0
    
    if [ -n "$COMPANY_IDS" ]; then
        COMPANY_COUNT=$(echo "$COMPANY_IDS" | wc -l | tr -d ' ')
        log_info "找到 $COMPANY_COUNT 个 Broker Groups"
        
        for company_id in $COMPANY_IDS; do
            if [ -z "$company_id" ] || [ "$company_id" = "null" ]; then
                continue
            fi
            
            log_info "删除 Broker Group ID: $company_id"
            DELETE_RESPONSE=$(call_api "DELETE" "/company/$company_id" "")
            DELETE_CODE=$(echo "$DELETE_RESPONSE" | jq -r '.code // empty' 2>/dev/null)
            
            if [ "$DELETE_CODE" = "0" ] || [ -z "$DELETE_CODE" ]; then
                log_success "  ✅ Broker Group ID $company_id 已删除"
                ((COMPANY_SUCCESS++))
            else
                log_error "  ❌ Broker Group ID $company_id 删除失败: $DELETE_RESPONSE"
                ((COMPANY_FAILED++))
            fi
        done
    else
        log_info "未找到任何 Broker Groups"
    fi
    
    echo ""
    log_info "Broker Groups 删除完成: 成功=$COMPANY_SUCCESS, 失败=$COMPANY_FAILED"
    
    # 总结
    echo ""
    log_success "=========================================="
    log_success "  清理完成"
    log_success "=========================================="
    echo ""
    log_info "删除统计:"
    echo "  - Brokers: 成功=$BROKER_SUCCESS, 失败=$BROKER_FAILED"
    echo "  - Broker Groups: 成功=$COMPANY_SUCCESS, 失败=$COMPANY_FAILED"
    echo ""
}

# 如果仅清理，执行清理后退出
if [ "$CLEAN_ONLY" = "true" ]; then
    clean_cloud_data
    exit $?
fi

# 如果需要先清理，执行清理
if [ "$CLEAN_BEFORE_MIGRATE" = "true" ]; then
    log_info "步骤 0: 清理云端数据..."
    echo ""
    if ! clean_cloud_data; then
        log_error "清理失败，停止迁移"
        exit 1
    fi
    echo ""
    log_success "清理完成，开始迁移..."
    echo ""
fi

# 步骤 1: 迁移 Broker Groups
log_info "步骤 1: 迁移 Broker Groups..."
echo ""
"$SCRIPT_DIR/migrate-broker-groups.sh" 2>&1 | tee -a "$LOG_FILE"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Broker Groups 迁移失败，停止迁移"
    exit 1
fi

echo ""
log_success "Broker Groups 迁移完成"
echo ""

# 检查 ID 映射文件
if [ ! -f "$MAPPING_FILE" ]; then
    log_error "ID 映射文件不存在: $MAPPING_FILE"
    log_error "Broker Groups 迁移可能失败"
    exit 1
fi

MAPPING_COUNT=$(wc -l < "$MAPPING_FILE" | tr -d ' ')
log_info "ID 映射文件包含 $MAPPING_COUNT 个映射关系"
echo ""

# 步骤 2: 迁移 Brokers
log_info "步骤 2: 迁移 Brokers..."
echo ""
"$SCRIPT_DIR/migrate-brokers.sh" 2>&1 | tee -a "$LOG_FILE"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Brokers 迁移失败"
    exit 1
fi

echo ""
log_success "所有数据迁移完成！"
echo ""

# 生成迁移报告
generate_migration_report() {
    log_info "生成迁移报告..."
    
    REPORT_FILE="$SCRIPT_DIR/migration-report-${TIMESTAMP}.txt"
    
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
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        log_warn "无法获取 token，报告中将缺少云端数据统计"
        TOKEN=""
    fi
    
    # API 调用函数
    call_api() {
        local method=$1
        local endpoint=$2
        if [ -z "$TOKEN" ]; then
            echo ""
            return
        fi
        curl -s -X "$method" "${API_BASE_URL}${endpoint}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json"
    }
    
    # 查询云端数据
    CLOUD_BROKER_GROUPS=0
    CLOUD_BROKERS_TOTAL=0
    CLOUD_BROKERS_DIRECT=0
    CLOUD_BROKERS_NON_DIRECT=0
    
    if [ -n "$TOKEN" ]; then
        # 查询 Broker Groups
        COMPANIES_RESPONSE=$(call_api "GET" "/company?type=BROKER_GROUP")
        if [ -n "$COMPANIES_RESPONSE" ]; then
            CLOUD_BROKER_GROUPS=$(echo "$COMPANIES_RESPONSE" | jq -r '.data.companies | length' 2>/dev/null || echo "0")
        fi
        
        # 查询 Brokers
        BROKERS_RESPONSE=$(call_api "GET" "/broker")
        if [ -n "$BROKERS_RESPONSE" ]; then
            CLOUD_BROKERS_TOTAL=$(echo "$BROKERS_RESPONSE" | jq -r '.data.brokers | length' 2>/dev/null || echo "0")
            CLOUD_BROKERS_DIRECT=$(echo "$BROKERS_RESPONSE" | jq -r '[.data.brokers[]? | select(.type == "DIRECT_PAYMENT" or .type == 1)] | length' 2>/dev/null || echo "0")
            CLOUD_BROKERS_NON_DIRECT=$(echo "$BROKERS_RESPONSE" | jq -r '[.data.brokers[]? | select(.type == "NON_DIRECT_PAYMENT" or .type == 2)] | length' 2>/dev/null || echo "0")
        fi
    fi
    
    # 从日志文件中提取统计信息
    # Broker Groups 统计
    BROKER_GROUP_SUCCESS=$(grep -E "Broker Group ID [0-9]+ -> [0-9]+:" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    BROKER_GROUP_SKIPPED=$(grep -E "Broker Group ID [0-9]+ 已存在" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    BROKER_GROUP_FAILED=$(grep -E "Broker Group ID [0-9]+ 迁移失败" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    
    # 尝试从子脚本的输出行中提取统计
    BROKER_GROUP_STATS=$(grep -E "Broker Group 迁移完成:" "$LOG_FILE" 2>/dev/null | tail -1)
    if [ -n "$BROKER_GROUP_STATS" ]; then
        BROKER_GROUP_SUCCESS=$(echo "$BROKER_GROUP_STATS" | grep -oE "成功: [0-9]+" | grep -oE "[0-9]+" || echo "$BROKER_GROUP_SUCCESS")
        BROKER_GROUP_SKIPPED=$(echo "$BROKER_GROUP_STATS" | grep -oE "跳过: [0-9]+" | grep -oE "[0-9]+" || echo "$BROKER_GROUP_SKIPPED")
        BROKER_GROUP_FAILED=$(echo "$BROKER_GROUP_STATS" | grep -oE "失败: [0-9]+" | grep -oE "[0-9]+" || echo "$BROKER_GROUP_FAILED")
    fi
    
    # NON_DIRECT_PAYMENT Brokers 统计
    NON_DIRECT_STATS=$(grep -E "NON_DIRECT_PAYMENT Broker 迁移完成:" "$LOG_FILE" 2>/dev/null | tail -1)
    if [ -n "$NON_DIRECT_STATS" ]; then
        NON_DIRECT_SUCCESS=$(echo "$NON_DIRECT_STATS" | grep -oE "成功: [0-9]+" | grep -oE "[0-9]+" || echo "0")
        NON_DIRECT_SKIPPED=$(echo "$NON_DIRECT_STATS" | grep -oE "跳过: [0-9]+" | grep -oE "[0-9]+" || echo "0")
        NON_DIRECT_FAILED=$(echo "$NON_DIRECT_STATS" | grep -oE "失败: [0-9]+" | grep -oE "[0-9]+" || echo "0")
    else
        NON_DIRECT_SUCCESS=$(grep -E "Broker ID [0-9]+ -> [0-9]+:" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        NON_DIRECT_SKIPPED=$(grep -E "Broker ID [0-9]+ 已存在\|跳过 broker ID" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        NON_DIRECT_FAILED=$(grep -E "Broker ID [0-9]+ 迁移失败" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi
    
    # DIRECT_PAYMENT Brokers 统计
    DIRECT_STATS=$(grep -E "DIRECT_PAYMENT Broker 迁移完成:" "$LOG_FILE" 2>/dev/null | tail -1)
    if [ -n "$DIRECT_STATS" ]; then
        DIRECT_SUCCESS=$(echo "$DIRECT_STATS" | grep -oE "成功: [0-9]+" | grep -oE "[0-9]+" || echo "0")
        DIRECT_SKIPPED=$(echo "$DIRECT_STATS" | grep -oE "跳过: [0-9]+" | grep -oE "[0-9]+" || echo "0")
        DIRECT_FAILED=$(echo "$DIRECT_STATS" | grep -oE "失败: [0-9]+" | grep -oE "[0-9]+" || echo "0")
    else
        DIRECT_SUCCESS=$(grep -E "Sub-Broker ID [0-9]+ -> [0-9]+:" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        DIRECT_SKIPPED=$(grep -E "Sub-Broker ID [0-9]+ 已存在\|跳过 sub_broker ID" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        DIRECT_FAILED=$(grep -E "Sub-Broker ID [0-9]+ 迁移失败" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi
    
    # 生成报告
    {
        echo "# 数据迁移报告"
        echo "# 生成时间: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# 数据来源: ${ENVIRONMENT} 环境"
        echo "# 目标环境: ${API_BASE_URL:-http://13.54.207.94/api}"
        echo ""
        echo "## 迁移统计"
        echo ""
        echo "### Broker Groups"
        echo "- **成功**: ${BROKER_GROUP_SUCCESS}个"
        echo "- **跳过**: ${BROKER_GROUP_SKIPPED}个（已存在）"
        echo "- **失败**: ${BROKER_GROUP_FAILED}个"
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
        echo "---"
        echo ""
        echo "## 云端数据状态"
        echo ""
        echo "### 当前云端数据（迁移后）"
        echo "- **Broker Groups**: ${CLOUD_BROKER_GROUPS}个"
        echo "- **Brokers (总计)**: ${CLOUD_BROKERS_TOTAL}个"
        echo "  - DIRECT_PAYMENT: ${CLOUD_BROKERS_DIRECT}个"
        echo "  - NON_DIRECT_PAYMENT: ${CLOUD_BROKERS_NON_DIRECT}个"
        echo ""
        echo "---"
        echo ""
        echo "## 相关文件"
        echo ""
        echo "- **ID 映射文件**: $MAPPING_FILE"
        echo "- **日志文件**: $LOG_FILE"
        echo "- **报告文件**: $REPORT_FILE"
        echo ""
        echo "---"
        echo ""
        echo "## 迁移详情"
        echo ""
        echo "### 环境信息"
        echo "- **环境**: ${ENVIRONMENT}"
        echo "- **API 地址**: ${API_BASE_URL:-http://13.54.207.94/api}"
        echo "- **映射文件**: $MAPPING_FILE"
        echo "- **映射关系数**: ${MAPPING_COUNT}个"
        echo ""
        if [ "$CLEAN_BEFORE_MIGRATE" = "true" ]; then
            echo "- **清理操作**: 已执行（迁移前清理云端数据）"
        fi
        echo ""
        echo "### 失败记录"
        echo ""
        if [ "$BROKER_GROUP_FAILED" -gt 0 ] || [ "$NON_DIRECT_FAILED" -gt 0 ] || [ "$DIRECT_FAILED" -gt 0 ]; then
            echo "请查看日志文件获取详细失败信息: $LOG_FILE"
        else
            echo "✅ 没有失败的记录"
        fi
        echo ""
    } > "$REPORT_FILE"
    
    log_success "迁移报告已生成: $REPORT_FILE"
    echo ""
    log_info "迁移结果:"
    echo "  - ID 映射文件: $MAPPING_FILE"
    echo "  - 日志文件: $LOG_FILE"
    echo "  - 迁移报告: $REPORT_FILE"
    echo "  - 包含 Broker Group ID 映射关系"
    echo ""
}

# 生成迁移报告
generate_migration_report

