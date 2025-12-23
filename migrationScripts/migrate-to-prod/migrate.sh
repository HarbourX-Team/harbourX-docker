#!/bin/bash

# 生产环境完整迁移脚本（单文件版本）
# 目标：仅保留一个 migrate.sh（迁移）+ 一个 fix.sh（修复），不依赖其他脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
echo_info(){ echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success(){ echo -e "${GREEN}✅ $1${NC}"; }
echo_warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error(){ echo -e "${RED}❌ $1${NC}"; }

[ -n "$LOGIN_PASSWORD" ] || { echo_error "生产环境需要提供 LOGIN_PASSWORD (export LOGIN_PASSWORD=...)"; exit 1; }
echo ""; echo_info "=========================================="; echo_info "  生产环境数据迁移"; echo_info "  目标: ${API_BASE_URL}"; echo_info "=========================================="; echo ""; echo_warn "⚠️  警告: 您正在迁移到生产环境！"
read -p "确认继续? (yes/no): " confirm; [ "$confirm" = "yes" ] || { echo "已取消"; exit 0; }

# 干跑模式：设置 DRY_RUN=true 将不执行任何外部请求/数据库写入，仅打印计划
DRY_RUN="${DRY_RUN:-false}"
if [ "$DRY_RUN" = "true" ]; then
  echo_info "Dry-run 模式: 不会对 API 或数据库进行任何更改"
  echo ""
  echo_info "配置概览:"
  echo "  API_BASE_URL: $API_BASE_URL"
  echo "  登录邮箱:     ${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
  echo "  老库 (K8S):   USE_PORT_FORWARD=${USE_PORT_FORWARD:-false}, KUBECONFIG_FILE=${KUBECONFIG_FILE:-<未设>}"
  echo "  老库连接:     $OLD_DB_USER@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME"
  echo "  本地数据库:   ${LOCAL_DB_USER:-postgres}@${LOCAL_DB_HOST:-localhost}:${LOCAL_DB_PORT:-5432}/${LOCAL_DB_NAME:-harbourx}"
  echo "  映射文件:     $SCRIPT_DIR/id_mapping.txt"
  echo ""
  echo_info "将执行的步骤:"
  echo "  1) 迁移 Broker Groups（查询老库、创建/复用新公司、保存映射、修复 Aggregator 绑定）"
  echo "  2) 迁移 Brokers（含 NON_DIRECT 与 DIRECT/sub_broker，修正 broker group 映射并重试）"
  echo "  3) 自动执行 fix.sh 修复 created_at/deleted_at"
  echo ""
  echo_success "Dry-run 检查通过：脚本可执行上述步骤。设置 DRY_RUN=false 以开始实际迁移。"
  exit 0
fi

# 端口转发与清理
PORT_FORWARD_PID=""
cleanup(){ if [ -n "$PORT_FORWARD_PID" ]; then echo_info "关闭 port-forward (PID: $PORT_FORWARD_PID)..."; kill $PORT_FORWARD_PID 2>/dev/null || true; wait $PORT_FORWARD_PID 2>/dev/null || true; PORT_FORWARD_PID=""; fi; }
trap cleanup EXIT INT TERM

# 工具检测
command -v jq >/dev/null 2>&1 || { echo_error "jq 未安装，请先安装: brew install jq"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo_error "psql 未安装，请先安装"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo_error "curl 未安装"; exit 1; }

# 如需要，启动到老库的 port-forward
if [ "${USE_PORT_FORWARD:-false}" = "true" ]; then
  command -v kubectl >/dev/null 2>&1 || { echo_error "kubectl 未安装，请先安装"; exit 1; }
  [ -f "$KUBECONFIG_FILE" ] || { echo_error "KUBECONFIG 文件不存在: $KUBECONFIG_FILE"; exit 1; }
  export KUBECONFIG="$KUBECONFIG_FILE"; echo_info "使用 Kubernetes port-forward 连接数据库: $KUBERNETES_SERVICE -> localhost:${PORT_FORWARD_PORT:-5434}"
  if lsof -Pi :${PORT_FORWARD_PORT:-5434} -sTCP:LISTEN -t >/dev/null 2>&1; then lsof -ti:${PORT_FORWARD_PORT:-5434} | xargs kill -9 2>/dev/null || true; sleep 2; fi
  kubectl port-forward "svc/${KUBERNETES_SERVICE:-broker-db}" "${PORT_FORWARD_PORT:-5434}:5432" >/dev/null 2>&1 & PORT_FORWARD_PID=$!; sleep 3
  kill -0 $PORT_FORWARD_PID 2>/dev/null || { echo_error "port-forward 启动失败"; exit 1; }
  OLD_DB_HOST="localhost"; OLD_DB_PORT="${PORT_FORWARD_PORT:-5434}"; echo_success "port-forward 已启动 (PID: $PORT_FORWARD_PID)"
fi

# 登录获取 token（支持预设 TOKEN 跳过登录）
if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
  echo_info "使用预设 TOKEN 跳过登录"
else
  echo_info "获取认证 token..."
  # 从 config.sh 加载的 LOGIN_EMAIL 和 LOGIN_PASSWORD 优先，如果没有则使用默认值
  # 如果环境变量中设置了错误的邮箱（如 admin@harbourx.com.au），则使用 config.sh 中的默认值
  if [ "${LOGIN_EMAIL}" = "admin@harbourx.com.au" ]; then
    echo_warn "检测到 LOGIN_EMAIL=admin@harbourx.com.au（该用户不存在），将使用 config.sh 中的默认值"
    unset LOGIN_EMAIL
  fi
  LOGIN_EMAIL="${LOGIN_EMAIL:-haimoneySupport@harbourx.com.au}"
  LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"
  
  echo_info "  登录邮箱: ${LOGIN_EMAIL}"
  echo_info "  API 地址: ${API_BASE_URL%/api}/api/auth/login"
  
  set +e
  LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_BASE_URL%/api}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
      \"identityType\": \"EMAIL\",
      \"identity\": \"${LOGIN_EMAIL}\",
      \"password\": \"${LOGIN_PASSWORD}\"
    }" 2>&1)
  RET=$?
  set -e
  
  if [ $RET -ne 0 ]; then
    echo_error "curl 请求失败 (退出码: $RET)"
    echo_error "请检查："
    echo_error "  1. API 服务是否运行: ${API_BASE_URL%/api}/api/auth/login"
    echo_error "  2. 网络连接是否正常"
    exit 1
  fi
  
  HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')
  
  if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo_error "登录失败，HTTP 状态码: $HTTP_CODE"
    echo_error "响应: $RESPONSE_BODY"
    echo ""
    echo_warn "可能的解决方案："
    echo_warn "  1. 检查用户是否存在（本地环境可能需要运行数据库迁移）"
    echo_warn "  2. 尝试其他账户："
    echo_warn "     export LOGIN_EMAIL=systemadmin@harbourx.com.au"
    echo_warn "     export LOGIN_PASSWORD=password"
    echo_warn "  3. 或使用预设 TOKEN 跳过登录："
    echo_warn "     export TOKEN=your-jwt-token"
    echo ""
    echo_warn "当前配置："
    echo_warn "  LOGIN_EMAIL: ${LOGIN_EMAIL}"
    echo_warn "  LOGIN_PASSWORD: ${LOGIN_PASSWORD:+已设置（隐藏）}"
    exit 1
  fi
  
  TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.data.jwt // .data.token // .token // empty' 2>/dev/null)
  
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo_error "登录失败，无法获取 token"
    echo_error "响应: $RESPONSE_BODY"
    exit 1
  fi
  
  echo_success "登录成功"
fi

# 检查老库连接
echo_info "检查老数据库连接..."
if ! PGPASSWORD="${OLD_DB_PASS}" psql -h "${OLD_DB_HOST}" -p "${OLD_DB_PORT}" -U "${OLD_DB_USER}" -d "${OLD_DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1; then
  echo_error "无法连接到老数据库"; exit 1; fi
echo_success "老数据库连接正常"

# ID 映射与 API 工具
# 强制将映射文件保存到 migrate-to-local 目录，统一管理
ID_MAPPING_FILE="$(cd "$SCRIPT_DIR/../migrate-to-local" && pwd)/id_mapping.txt"
touch "$ID_MAPPING_FILE"

call_api(){ local m=$1; local e=$2; local d=$3; if [ -z "$d" ]; then curl -s -X "$m" "${API_BASE_URL}${e}" -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json"; else curl -s -X "$m" "${API_BASE_URL}${e}" -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d "$d"; fi; }

resolve_aggregator_company_id(){
  if [ -n "$AGGREGATOR_COMPANY_ID" ] && echo "$AGGREGATOR_COMPANY_ID" | grep -Eq '^[0-9]+$'; then echo "$AGGREGATOR_COMPANY_ID"; return 0; fi
  local resp=$(call_api GET "/company?type=AGGREGATOR&size=10" "" 2>/dev/null) || true
  local id=$(echo "$resp" | jq -r '.data.companies[0].id // empty')
  if [ -n "$id" ] && [ "$id" != "null" ]; then echo "$id"; return 0; fi
  # 生产环境：无法直接访问数据库，回退为 1
  echo_warn "无法自动解析 Aggregator Company ID，回退为 1；可通过环境变量 AGGREGATOR_COMPANY_ID 指定"; echo 1
}

find_existing_broker_group(){ local name=$1; local abn=$2; if [ -n "$abn" ] && [ "$abn" != "0" ]; then local abn_clean=$(echo "$abn" | tr -d ' '); local abn_encoded=$(echo "$abn_clean" | sed 's/ /%20/g'); local response=$(call_api GET "/company?abn=${abn_encoded}" "" 2>/dev/null); local id=$(echo "$response" | jq -r '.data.companies[0].id // empty'); [ -n "$id" ] && [ "$id" != "null" ] && { echo "$id"; return 0; }; fi; local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null); local name_escaped=$(echo "$name" | sed 's/"/\\"/g'); local id=$(echo "$response" | jq -r ".data.companies[] | select(.name == \"$name_escaped\") | .id" 2>/dev/null | head -1); [ -n "$id" ] && [ "$id" != "null" ] && { echo "$id"; return 0; }; return 1; }

get_crn_from_acr(){ local broker_name="$1"; [ -f "$ACR_CRN_MAPPING_FILE" ] || { echo ""; return; }; local crn=$(awk -F',' -v name="$broker_name" 'BEGIN{gsub(/^"|"$/,"",name);name=tolower(name);gsub(/^[[:space:]]+|[[:space:]]+$/,"",name)} NR>1{gsub(/^"|"$/,"",$1);gsub(/^"|"$/,"",$2);f=tolower($1);gsub(/^[[:space:]]+|[[:space:]]+$/,"",f); if(f==name){print $2; exit}}' "$ACR_CRN_MAPPING_FILE"); if [ -z "$crn" ]; then crn=$(awk -F',' -v name="$broker_name" 'BEGIN{gsub(/^"|"$/,"",name);name=tolower(name);gsub(/^[[:space:]]+|[[:space:]]+$/,"",name)} NR>1{gsub(/^"|"$/,"",$1);gsub(/^"|"$/,"",$2);f=tolower($1);gsub(/^[[:space:]]+|[[:space:]]+$/,"",f); if(index(f,name)>0 || index(name,f)>0){print $2; exit}}' "$ACR_CRN_MAPPING_FILE"); fi; echo "$crn"; }

migrate_broker_groups(){
  echo ""; echo_info "步骤 1: 迁移 Broker Groups..."
  
  # 优先迁移三个特殊的 broker group（用于硬编码映射）
  echo_info "优先迁移特殊 broker groups（用于硬编码映射）..."
  local special_bg_names=("Great Life Finance Pty Ltd" "PRESTIGE CAPITAL ADVISORS PTY LTD" "Model Max Pty Ltd")
  local AGG_ID="${AGGREGATOR_COMPANY_ID:-}"; [ -z "$AGG_ID" ] && AGG_ID=$(resolve_aggregator_company_id) && echo_info "使用 Aggregator Company ID: $AGG_ID"
  
  for special_name in "${special_bg_names[@]}"; do
    # 检查是否已存在
    local existing_id=$(find_existing_broker_group "$special_name" "" 2>/dev/null || echo "")
    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
      echo_info "  Broker Group '$special_name' 已存在 (ID: $existing_id)"
      continue
    fi
    
    # 从老系统查找
    local old_bg_info=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -c "SELECT id, name, abn, account_name, bsb_number, account_number, email, phone, address FROM broker_group WHERE name = '$special_name' AND deleted IS NULL LIMIT 1;" 2>/dev/null)
    if [ -n "$old_bg_info" ]; then
      IFS='|' read -r oid name abn acc_name bsb acc_no email phone address <<< "$old_bg_info"
      oid=$(echo "$oid" | tr -d ' ')
      name=$(echo "$name" | sed 's/^\s*//;s/\s*$//')
      echo_info "  从老系统找到 Broker Group: $name (老ID: $oid)，正在迁移..."
      
      local abn_clean=$(echo "$abn" | tr -d -c '0-9'); local bsb_clean=$(echo "$bsb" | tr -d -c '0-9'); local account_clean=$(echo "$acc_no" | tr -d -c '0-9')
      [ -z "$abn_clean" ] || [ "$abn_clean" = "0" ] && abn_clean="1000000000${oid}"
      [ -z "$acc_name" ] || [ "$acc_name" = "NULL" ] && acc_name="${name} Bank Account"
      [ -z "$bsb_clean" ] || [ "$bsb_clean" = "0" ] && bsb_clean="123456"
      [ -z "$account_clean" ] || [ "$account_clean" = "0" ] && account_clean="12345678"
      
      local json=$(jq -n --arg name "$name" --argjson abn "$abn_clean" --arg bank_account_name "$acc_name" --argjson bsb "$bsb_clean" --argjson account "$account_clean" --argjson aggregator_id "$AGG_ID" --arg email "$email" --arg phone "$phone" --arg address "$address" '{name:$name,abn:$abn,bankAccountName:$bank_account_name,bankAccountBsb:$bsb,bankAccountNumber:$account,aggregatorCompanyId:$aggregator_id} + (if $email != "" and $email != "NULL" then {email:$email} else {} end) + (if $phone != "" and $phone != "NULL" then {phoneNumber:$phone} else {} end) + (if $address != "" and $address != "NULL" then {address:$address} else {} end)')
      local resp=$(call_api POST "/company/broker-group" "$json"); local code=$(echo "$resp" | jq -r '.code // "unknown"'); local nid=$(echo "$resp" | jq -r '.data.companies[0].id // empty')
      if [ "$code" = "0" ] && [ -n "$nid" ] && [ "$nid" != "null" ]; then
        echo_success "  成功迁移 Broker Group $oid -> $nid: $name"
        # 生产环境：created_at 修复将通过 fix.sh prod 完成
        echo "$oid:$nid" >> "$ID_MAPPING_FILE"
      else
        echo_warn "  迁移失败: $name (响应: $resp)"
      fi
    else
      echo_warn "  在老系统中未找到 Broker Group: $special_name"
    fi
  done
  echo ""
  
  # 清理错误的 (Old) broker groups（通过 API 查找）
  echo_info "清理错误的 (Old) broker groups..."
  local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
  local old_bg_ids=$(echo "$response" | jq -r '.data.companies[] | select((.name | test("(?i)\\(Old\\)")) or (.name | test("(?i)\\(old\\)"))) | "\(.id)|\(.name)"' 2>/dev/null)
  if [ -n "$old_bg_ids" ]; then
    while IFS='|' read -r old_bg_id old_bg_name || [ -n "$old_bg_id" ]; do
      [ -z "$old_bg_id" ] && continue
      old_bg_id=$(echo "$old_bg_id" | tr -d ' ')
      old_bg_name=$(echo "$old_bg_name" | sed 's/^\s*//;s/\s*$//')
      if [ -n "$old_bg_id" ] && [ "$old_bg_id" != "" ]; then
        echo_warn "发现错误的 (Old) broker group: $old_bg_name (ID: $old_bg_id)，正在删除..."
        local delete_resp=$(call_api DELETE "/company/$old_bg_id" "" 2>/dev/null || echo "")
        if echo "$delete_resp" | jq -e '.code == 0' >/dev/null 2>&1; then
          echo_success "  已删除错误的 (Old) broker group: $old_bg_name (ID: $old_bg_id)"
        else
          echo_warn "  删除失败，响应: $delete_resp"
        fi
      fi
    done <<< "$old_bg_ids"
  else
    echo_info "  未发现需要清理的 (Old) broker groups"
  fi
  
  TMP_DIR=$(mktemp -d)
  local CSV="$TMP_DIR/broker_groups.csv"
  PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT id, name, abn, account_name, bsb_number, account_number, email, phone, address FROM broker_group WHERE deleted IS NULL" -t -A -F"," > "$CSV"
  local count=$(wc -l < "$CSV" | tr -d ' '); echo_info "找到 $count 个 Broker Group 需要迁移"
  : > "${ID_MAPPING_FILE}.tmp"
  local AGG_ID="${AGGREGATOR_COMPANY_ID:-}"; [ -z "$AGG_ID" ] && AGG_ID=$(resolve_aggregator_company_id) && echo_info "使用 Aggregator Company ID: $AGG_ID"
  local ok=0 skip=0 fail=0
  while IFS=',' read -r oid name abn acc_name bsb acc_no email phone address || [ -n "$oid" ]; do
    [ -z "$oid" ] && continue; oid=$(echo "$oid" | tr -d ' '); name=$(echo "$name" | sed 's/^\s*//;s/\s*$//'); [ -z "$name" ] || [ "$name" = "NULL" ] && { ((skip++)); continue; }
    # 跳过包含 "(Old)" 的 broker group，这些会在 broker 迁移时映射到非 "(Old)" 版本
    if echo "$name" | grep -qi "(Old)"; then
      echo_warn "跳过 Broker Group $oid (Old): $name（将在 broker 迁移时映射到非 Old 版本）"
      # 检查是否已经错误地迁移了这个 (Old) broker group，如果是则删除（通过 API）
      local old_bg_id=$(find_existing_broker_group "$name" "" 2>/dev/null || echo "")
      if [ -n "$old_bg_id" ] && [ "$old_bg_id" != "" ] && [ "$old_bg_id" != "null" ]; then
        echo_warn "  发现已错误迁移的 (Old) broker group (ID: $old_bg_id)，正在删除..."
        local delete_resp=$(call_api DELETE "/company/$old_bg_id" "" 2>/dev/null || echo "")
        if echo "$delete_resp" | jq -e '.code == 0' >/dev/null 2>&1; then
          echo_success "  已删除错误的 (Old) broker group: $old_bg_id"
        else
          echo_warn "  删除失败，可能需要手动删除: $old_bg_id"
        fi
      fi
      ((skip++)); continue
    fi
    local abn_clean=$(echo "$abn" | tr -d -c '0-9'); local bsb_clean=$(echo "$bsb" | tr -d -c '0-9'); local account_clean=$(echo "$acc_no" | tr -d -c '0-9')
    [ -z "$abn_clean" ] || [ "$abn_clean" = "0" ] && abn_clean="1000000000${oid}"
    [ -z "$acc_name" ] || [ "$acc_name" = "NULL" ] && acc_name="${name} Bank Account"
    [ -z "$bsb_clean" ] || [ "$bsb_clean" = "0" ] && bsb_clean="123456"
    [ -z "$account_clean" ] || [ "$account_clean" = "0" ] && account_clean="12345678"
    local existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo "")
    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then echo_warn "Broker Group $oid 已存在 (新ID: $existing_id): $name"; echo "$oid:$existing_id" >> "${ID_MAPPING_FILE}.tmp"; ((skip++)); continue; fi
    local json=$(jq -n --arg name "$name" --argjson abn "$abn_clean" --arg bank_account_name "$acc_name" --argjson bsb "$bsb_clean" --argjson account "$account_clean" --argjson aggregator_id "$AGG_ID" --arg email "$email" --arg phone "$phone" --arg address "$address" '{name:$name,abn:$abn,bankAccountName:$bank_account_name,bankAccountBsb:$bsb,bankAccountNumber:$account,aggregatorCompanyId:$aggregator_id} + (if $email != "" and $email != "NULL" then {email:$email} else {} end) + (if $phone != "" and $phone != "NULL" then {phoneNumber:$phone} else {} end) + (if $address != "" and $address != "NULL" then {address:$address} else {} end)')
    local resp=$(call_api POST "/company/broker-group" "$json"); local code=$(echo "$resp" | jq -r '.code // "unknown"'); local nid=$(echo "$resp" | jq -r '.data.companies[0].id // empty')
    if [ "$code" = "0" ] && [ -n "$nid" ] && [ "$nid" != "null" ]; then
      echo_success "Broker Group $oid -> $nid: $name"
      # 生产环境：created_at 修复将通过 fix.sh prod 完成
      echo "$oid:$nid" >> "${ID_MAPPING_FILE}.tmp"
      ((ok++))
    elif echo "$resp" | grep -qi "already exists\|duplicate"; then existing_id=$(find_existing_broker_group "$name" "$abn_clean" 2>/dev/null || echo ""); [ -n "$existing_id" ] && echo "$oid:$existing_id" >> "${ID_MAPPING_FILE}.tmp"; ((skip++))
    else echo_error "Broker Group $oid 迁移失败: $name"; echo "  响应: $resp"; ((fail++)); fi
  done < "$CSV"
  if [ -s "${ID_MAPPING_FILE}.tmp" ]; then
    while IFS=: read -r a b; do
      if grep -q "^${a}:" "$ID_MAPPING_FILE" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
          sed -i '' "/^${a}:/d" "$ID_MAPPING_FILE"
        else
          sed -i.bak "/^${a}:/d" "$ID_MAPPING_FILE"
        fi
      fi
      echo "$a:$b" >> "$ID_MAPPING_FILE"
    done < "${ID_MAPPING_FILE}.tmp"
    rm -f "${ID_MAPPING_FILE}.tmp"
  fi
  echo_info "Broker Groups 迁移完成: 成功 $ok, 跳过 $skip, 失败 $fail"

  # 生产环境：Aggregator 绑定修复将通过 fix.sh prod 完成
  echo_info "Broker Groups 与 Aggregator 关系将在 fix.sh prod 中修复"
}

migrate_brokers(){
  echo ""; echo_info "步骤 2: 迁移 Brokers..."
  
  # 清理错误的 Dong Lee brokers（通过 API 查找）
  echo_info "清理错误的 Dong Lee brokers..."
  local broker_response=$(call_api GET "/broker?size=2000" "" 2>/dev/null)
  local wrong_broker_ids=$(echo "$broker_response" | jq -r '.data.brokers[]? | select((.name | test("(?i).*Dong.*Lee.*")) or (.name | test("(?i).*Dong.*Sik.*"))) | select(.name != "Dong Lee") | "\(.id)|\(.name)"' 2>/dev/null)
  if [ -n "$wrong_broker_ids" ]; then
    while IFS='|' read -r wrong_broker_id wrong_broker_name || [ -n "$wrong_broker_id" ]; do
      [ -z "$wrong_broker_id" ] && continue
      wrong_broker_id=$(echo "$wrong_broker_id" | tr -d ' ')
      wrong_broker_name=$(echo "$wrong_broker_name" | sed 's/^\s*//;s/\s*$//')
      if [ -n "$wrong_broker_id" ] && [ "$wrong_broker_id" != "" ]; then
        echo_warn "发现错误的 broker: $wrong_broker_name (ID: $wrong_broker_id)，正在删除..."
        local delete_resp=$(call_api DELETE "/broker/$wrong_broker_id" "" 2>/dev/null || echo "")
        if echo "$delete_resp" | jq -e '.code == 0' >/dev/null 2>&1; then
          echo_success "  已删除错误的 broker: $wrong_broker_name (ID: $wrong_broker_id)"
        else
          echo_warn "  删除失败，响应: $delete_resp"
        fi
      fi
    done <<< "$wrong_broker_ids"
  else
    echo_info "  未发现需要清理的错误 Dong Lee brokers"
  fi
  
  # 诊断未迁移的 broker
  echo_info "诊断已知的未迁移 broker..."
  local missing_broker_names=("William (Bill) Gilmour" "Jing (Kayla) Kang" "Hong Gu" "Bozhi Li" "Sopheak (Charlie) Chhaing" "Yan (Anna) Zhang" "Jie (Jane) Xu" "Yiwen (Vicky) Hu")
  local missing_count=0
  for broker_name in "${missing_broker_names[@]}"; do
    local broker_info=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -c "SELECT id, name, broker_group_id, sub_broker_id, deleted FROM broker WHERE name = '$broker_name' LIMIT 1;" 2>/dev/null)
    if [ -n "$broker_info" ]; then
      IFS='|' read -r old_id old_name bg_id sub_id deleted <<< "$broker_info"
      old_id=$(echo "$old_id" | tr -d ' ')
      bg_id=$(echo "$bg_id" | tr -d ' ')
      sub_id=$(echo "$sub_id" | tr -d ' ')
      deleted=$(echo "$deleted" | tr -d ' ')
      echo_warn "发现未迁移的 broker: $broker_name"
      echo_warn "  老系统 ID: $old_id"
      echo_warn "  broker_group_id: ${bg_id:-NULL}"
      echo_warn "  sub_broker_id: ${sub_id:-NULL}"
      echo_warn "  deleted: ${deleted:-NULL}"
      if [ -z "$bg_id" ] || [ "$bg_id" = "0" ] || [ "$bg_id" = "NULL" ]; then
        echo_warn "  原因: broker_group_id 为 NULL 或 0，无法迁移（需要先迁移 broker_group）"
        ((missing_count++))
      elif [ -n "$sub_id" ] && [ "$sub_id" != "0" ] && [ "$sub_id" != "NULL" ]; then
        echo_warn "  原因: 有 sub_broker_id ($sub_id)，可能被排除"
        ((missing_count++))
      elif [ -n "$deleted" ] && [ "$deleted" != "NULL" ]; then
        echo_warn "  原因: 被标记为 deleted"
        ((missing_count++))
      else
        echo_warn "  原因: 可能 broker_group ($bg_id) 没有被迁移"
        ((missing_count++))
      fi
    else
      echo_info "  $broker_name: 在老系统中未找到"
    fi
  done
  if [ "$missing_count" -gt 0 ]; then
    echo_warn "共发现 $missing_count 个已知的未迁移 broker"
  fi
  echo ""
  
  # 检查 broker_group_id 为 NULL 或 0 的 broker 数量
  local null_bg_count=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -c "SELECT COUNT(*) FROM broker WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NULL OR broker_group_id = 0) AND id NOT IN (SELECT DISTINCT sub_broker_id FROM broker WHERE sub_broker_id IS NOT NULL AND sub_broker_id != 0);" 2>/dev/null | tr -d ' ')
  if [ -n "$null_bg_count" ] && [ "$null_bg_count" != "0" ]; then
    echo_warn "发现 $null_bg_count 个 broker 的 broker_group_id 为 NULL 或 0，这些 broker 无法迁移"
    echo_warn "  需要先迁移这些 broker 的 broker_group，或者为它们创建默认的 broker_group"
  fi
  
  TMP2=$(mktemp -d)
  # NON_DIRECT - 包含已知的特殊 broker（即使 broker_group_id 为 0）
  local CSV1="$TMP2/brokers.csv"
  
  # 预加载所有已存在的 broker（生产环境：通过 API 查询一次，避免循环内重复查询）
  echo_info "预加载已存在的 broker 列表..."
  # 尝试获取所有brokers（可能需要多次查询如果支持分页）
  local existing_brokers_response=$(call_api GET "/broker?size=2000" "" 2>/dev/null)
  local existing_brokers_cache="$TMP2/existing_brokers.json"
  echo "$existing_brokers_response" > "$existing_brokers_cache" 2>/dev/null || true
  # 调试：输出实际broker数量（不使用local，确保在函数内所有地方可用）
  actual_broker_count=$(echo "$existing_brokers_response" | jq -r '.data.brokers | length' 2>/dev/null || echo "0")
  local total_count=$(echo "$existing_brokers_response" | jq -r '.data.total // .total // 0' 2>/dev/null || echo "0")
  echo_info "生产环境中实际存在的 broker 数量: $actual_broker_count (API返回的brokers数组长度)"
  if [ -n "$total_count" ] && [ "$total_count" != "0" ] && [ "$total_count" != "null" ]; then
    echo_info "API返回的总数: $total_count"
    if [ "$total_count" -gt "$actual_broker_count" ]; then
      echo_warn "⚠️  警告：API返回的总数 ($total_count) 大于当前查询的brokers数量 ($actual_broker_count)，可能存在分页问题"
    fi
  fi
  if [ "$actual_broker_count" -lt 50 ]; then
    echo_warn "⚠️  警告：生产环境中只有 $actual_broker_count 个brokers，可能数据不完整或存在分页问题"
    echo_warn "将强制迁移所有brokers，即使名称匹配也会尝试创建（如果API返回duplicate错误则跳过）"
  fi
  # 首先查询正常的 broker（broker_group_id 不为 0）
  # 使用管道符作为分隔符，避免name字段中的逗号导致解析错误
  PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT id, name, broker_group_id, infinity_id FROM broker WHERE deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) AND (broker_group_id IS NOT NULL AND broker_group_id != 0) AND id NOT IN (SELECT DISTINCT sub_broker_id FROM broker WHERE sub_broker_id IS NOT NULL AND sub_broker_id != 0)" -t -A -F"|" > "$CSV1"
  # 然后添加已知的特殊 broker（broker_group_id 为 0 或 NULL，但需要特殊处理）
  local special_broker_names=("William (Bill) Gilmour" "Jing (Kayla) Kang" "Hong Gu" "Bozhi Li" "Sopheak (Charlie) Chhaing" "Yan (Anna) Zhang" "Jie (Jane) Xu" "Yiwen (Vicky) Hu")
  for special_name in "${special_broker_names[@]}"; do
    # 使用管道符作为分隔符，避免 name 字段中的逗号导致解析错误
    local special_info=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -F"|" -c "SELECT id, name, COALESCE(broker_group_id, 0), COALESCE(infinity_id, 0) FROM broker WHERE name = '$special_name' AND deleted IS NULL AND (sub_broker_id IS NULL OR sub_broker_id = 0) LIMIT 1;" 2>/dev/null)
    if [ -n "$special_info" ]; then
      # 解析管道符分隔的数据
      IFS='|' read -r special_id special_name_db special_bg_id special_inf_id <<< "$special_info"
      special_id=$(echo "$special_id" | tr -d ' ')
      special_bg_id=$(echo "$special_bg_id" | tr -d ' ')
      special_inf_id=$(echo "$special_inf_id" | tr -d ' ')
      # 检查是否已经在 CSV 中（使用管道符格式检查）
      if ! grep -q "^${special_id}|" "$CSV1" 2>/dev/null; then
        # 使用管道符格式写入 CSV
        echo "${special_id}|${special_name_db}|${special_bg_id}|${special_inf_id}" >> "$CSV1"
        echo_info "添加特殊 broker 到迁移列表: $special_name_db (ID: $special_id, bg_id: $special_bg_id)"
      fi
    else
      echo_warn "未找到特殊 broker: $special_name"
    fi
  done
  local cnt=$(wc -l < "$CSV1" | tr -d ' '); echo_info "NON_DIRECT 待迁移: $cnt (包含特殊 broker)"
  local ok=0 sk=0 fl=0
  local AGG_ID="${AGGREGATOR_COMPANY_ID:-}"; [ -z "$AGG_ID" ] && AGG_ID=$(resolve_aggregator_company_id)
  local skipped_log="$TMP2/skipped_brokers.log"
  : > "$skipped_log"
  
  while IFS='|' read -r oid name bg_id inf_id || [ -n "$oid" ]; do
    [ -z "$oid" ] && continue
    oid=$(echo "$oid" | tr -d ' ')
    
    # 处理 name 字段，可能包含逗号或其他特殊字符
    # 如果 name 字段包含逗号，IFS 会错误分割，需要特殊处理
    # 先尝试正常解析
    name=$(echo "$name" | sed 's/^\s*//;s/\s*$//')
    bg_id=$(echo "$bg_id" | tr -d ' ')
    inf_id=$(echo "$inf_id" | tr -d ' ')
    
    # 如果 name 为空，可能是 CSV 解析错误
    # 尝试重新解析整行（使用管道符分隔符）
    if [ -z "$name" ] || [ "$name" = "NULL" ]; then
      # 从原始行重新解析
      local full_line=$(grep "^${oid}|" "$CSV1" 2>/dev/null | head -1)
      if [ -n "$full_line" ]; then
        IFS='|' read -r oid name bg_id inf_id <<< "$full_line"
        oid=$(echo "$oid" | tr -d ' ')
        name=$(echo "$name" | sed 's/^\s*//;s/\s*$//')
        bg_id=$(echo "$bg_id" | tr -d ' ')
        inf_id=$(echo "$inf_id" | tr -d ' ')
      fi
    fi
    
    # 调试：对于特殊 broker，输出原始数据
    case "$name" in
      *"William"*"Gilmour"*|*"Bozhi"*"Li"*|*"Yan"*"Zhang"*)
        echo_info "调试: Broker ID $oid, 解析后的 name: '$name', bg_id: '$bg_id'"
        ;;
    esac
    
    [ -z "$name" ] || [ "$name" = "NULL" ] && { 
      echo_warn "Broker ID $oid: name 为空或 NULL，原始行: $(grep "^${oid}|" "$CSV1" 2>/dev/null | head -1)"
      echo "SKIP_EMPTY_NAME|$oid|$name|$bg_id|" >> "$skipped_log"
      ((sk++)); continue
    }
    # 如果 broker_group_id 为 0 或 NULL，设置为 0 以便后续处理
    [ -z "$bg_id" ] || [ "$bg_id" = "NULL" ] && bg_id="0"
    
    local name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40); local email="${name_clean}_${oid}@migrated.local"
    local crn=$(get_crn_from_acr "$name"); [ -z "$crn" ] && crn="CRN_BROKER_${oid}"
    
    # 检查新系统中是否已存在此 broker（生产环境：使用预加载的缓存）
    # 注意：如果生产环境中broker数量很少（<50），则强制迁移所有brokers
    local existing_in_new=""
    if [ -f "$existing_brokers_cache" ] && [ "$actual_broker_count" -ge 50 ]; then
      local name_escaped=$(echo "$name" | sed 's/"/\\"/g')
      existing_in_new=$(cat "$existing_brokers_cache" | jq -r ".data.brokers[] | select(.name == \"$name_escaped\") | .id" 2>/dev/null | head -1)
      [ -n "$existing_in_new" ] && [ "$existing_in_new" != "null" ] && existing_in_new=$(echo "$existing_in_new" | tr -d ' ')
    fi
    # 如果已存在且broker数量足够多，跳过创建；否则强制迁移（让API处理duplicate错误）
    if [ -n "$existing_in_new" ] && [ "$existing_in_new" != "" ] && [ "$existing_in_new" != "null" ] && [ "$actual_broker_count" -ge 50 ]; then
      echo_info "Broker $oid ($name): 已存在 (新系统ID: $existing_in_new)，跳过"
      ((sk++))
      continue
    fi
    
    local new_bg_id=""
    # 对于这三个特殊 broker，优先使用硬编码映射
    local is_special_broker=false
    case "$name" in
      "William (Bill) Gilmour"|"Bozhi Li"|"Yan (Anna) Zhang")
        is_special_broker=true
        ;;
    esac
    
    # 如果 broker_group_id 不为 0，先尝试从映射文件中查找（可能已经映射过了）
    if [ "$bg_id" != "0" ] && [ -n "$bg_id" ]; then
      new_bg_id=$(grep "^${bg_id}:" "$ID_MAPPING_FILE" | cut -d: -f2 | head -1)
      if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
        # 验证这个映射的 broker group 是否是我们期望的
        if [ "$is_special_broker" = "true" ]; then
          local expected_bg_name=""
          case "$name" in
            "William (Bill) Gilmour")
              expected_bg_name="Great Life Finance Pty Ltd"
              ;;
            "Bozhi Li")
              expected_bg_name="PRESTIGE CAPITAL ADVISORS PTY LTD"
              ;;
            "Yan (Anna) Zhang")
              expected_bg_name="Model Max Pty Ltd"
              ;;
          esac
          # 检查映射的 broker group 名称是否匹配
          local mapped_bg_name=$(PGPASSWORD="${LOCAL_DB_PASS:-postgres}" psql -h "${LOCAL_DB_HOST:-localhost}" -p "${LOCAL_DB_PORT:-5432}" -U "${LOCAL_DB_USER:-postgres}" -d "${LOCAL_DB_NAME:-harbourx}" -t -A -c "SELECT name FROM companies WHERE id = $new_bg_id AND type = 2;" 2>/dev/null | sed 's/^\s*//;s/\s*$//')
          if [ "$mapped_bg_name" = "$expected_bg_name" ]; then
            echo_info "Broker $oid ($name): 使用映射文件中已有的映射 - $expected_bg_name (ID: $new_bg_id)"
          else
            echo_warn "Broker $oid ($name): 映射文件中的 broker group (ID: $new_bg_id, 名称: $mapped_bg_name) 不匹配期望的 $expected_bg_name，将使用硬编码映射"
            new_bg_id=""
          fi
        fi
      fi
    fi
    
    # Hard-coded broker to broker group mappings (对于特殊 broker 且映射文件中没有找到正确映射的情况)
    if [ "$is_special_broker" = "true" ] && ([ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ] || [ "$new_bg_id" = "" ] || [ "$bg_id" = "0" ]); then
      case "$name" in
        "William (Bill) Gilmour")
          echo_info "Broker $oid ($name): 开始硬编码映射查找 'Great Life Finance Pty Ltd'..."
          new_bg_id=$(find_existing_broker_group "Great Life Finance Pty Ltd" "" 2>/dev/null || echo "")
          if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
            echo_success "Broker $oid ($name): 硬编码映射成功 - Great Life Finance Pty Ltd (ID: $new_bg_id)"
            # 如果 bg_id 为 0，使用一个虚拟的 ID 来记录映射
            if [ "$bg_id" = "0" ]; then
              echo "SPECIAL_${oid}:$new_bg_id" >> "$ID_MAPPING_FILE"
            else
              echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
            fi
          else
            echo_warn "Broker $oid ($name): 硬编码映射失败 - 未找到 'Great Life Finance Pty Ltd' broker group"
            echo_warn "  请确保该 broker group 已在步骤 1 中被迁移"
            # 尝试模糊匹配
            local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
            new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | ascii_downcase | gsub(\" \";\"\") | gsub(\"pty\";\"\") | gsub(\"ltd\";\"\")) | contains(\"greatlifefinance\")) | .id" 2>/dev/null | head -1)
            if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ] || [ "$new_bg_id" = "" ]; then
              new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\") | gsub(\"PTY\";\"\") | gsub(\"LTD\";\"\")) | test(\"Great.*Life.*Finance\"; \"i\")) | .id" 2>/dev/null | head -1)
            fi
            if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
              local found_name=$(echo "$response" | jq -r ".data.companies[] | select(.id == $new_bg_id) | .name" 2>/dev/null | head -1)
              echo_info "Broker $oid ($name): 通过模糊匹配找到 broker group: $found_name (ID: $new_bg_id)"
              echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
            else
              echo_error "Broker $oid ($name): 模糊匹配也失败，无法找到 'Great Life Finance Pty Ltd' broker group"
            fi
          fi
          ;;
        "Bozhi Li")
          echo_info "Broker $oid ($name): 开始硬编码映射查找 'PRESTIGE CAPITAL ADVISORS PTY LTD'..."
          new_bg_id=$(find_existing_broker_group "PRESTIGE CAPITAL ADVISORS PTY LTD" "" 2>/dev/null || echo "")
          if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
            echo_success "Broker $oid ($name): 硬编码映射成功 - PRESTIGE CAPITAL ADVISORS PTY LTD (ID: $new_bg_id)"
            if [ "$bg_id" = "0" ]; then
              echo "SPECIAL_${oid}:$new_bg_id" >> "$ID_MAPPING_FILE"
            else
              echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
            fi
          else
            echo_warn "Broker $oid ($name): 硬编码映射失败 - 未找到 'PRESTIGE CAPITAL ADVISORS PTY LTD' broker group"
            echo_warn "  请确保该 broker group 已在步骤 1 中被迁移"
            # 尝试模糊匹配
            local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
            new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\") | gsub(\"PTY\";\"\") | gsub(\"LTD\";\"\")) | test(\"PRESTIGE.*CAPITAL\"; \"i\")) | .id" 2>/dev/null | head -1)
            if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
              local found_name=$(echo "$response" | jq -r ".data.companies[] | select(.id == $new_bg_id) | .name" 2>/dev/null | head -1)
              echo_info "Broker $oid ($name): 通过模糊匹配找到 broker group: $found_name (ID: $new_bg_id)"
              if [ "$bg_id" = "0" ]; then
                echo "SPECIAL_${oid}:$new_bg_id" >> "$ID_MAPPING_FILE"
              else
                echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
              fi
            else
              echo_error "Broker $oid ($name): 模糊匹配也失败，无法找到 'PRESTIGE CAPITAL ADVISORS PTY LTD' broker group"
            fi
          fi
          ;;
        "Yan (Anna) Zhang")
          echo_info "Broker $oid ($name): 开始硬编码映射查找 'Model Max Pty Ltd'..."
          new_bg_id=$(find_existing_broker_group "Model Max Pty Ltd" "" 2>/dev/null || echo "")
          if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
            echo_success "Broker $oid ($name): 硬编码映射成功 - Model Max Pty Ltd (ID: $new_bg_id)"
            if [ "$bg_id" = "0" ]; then
              echo "SPECIAL_${oid}:$new_bg_id" >> "$ID_MAPPING_FILE"
            else
              echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
            fi
          else
            echo_warn "Broker $oid ($name): 硬编码映射失败 - 未找到 'Model Max Pty Ltd' broker group"
            echo_warn "  请确保该 broker group 已在步骤 1 中被迁移"
            # 尝试模糊匹配
            local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
            new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\") | gsub(\"PTY\";\"\") | gsub(\"LTD\";\"\")) | test(\"Model.*Max\"; \"i\")) | .id" 2>/dev/null | head -1)
            if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ] && [ "$new_bg_id" != "" ]; then
              local found_name=$(echo "$response" | jq -r ".data.companies[] | select(.id == $new_bg_id) | .name" 2>/dev/null | head -1)
              echo_info "Broker $oid ($name): 通过模糊匹配找到 broker group: $found_name (ID: $new_bg_id)"
              if [ "$bg_id" = "0" ]; then
                echo "SPECIAL_${oid}:$new_bg_id" >> "$ID_MAPPING_FILE"
              else
                echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
              fi
            else
              echo_error "Broker $oid ($name): 模糊匹配也失败，无法找到 'Model Max Pty Ltd' broker group"
            fi
          fi
          ;;
      esac
    fi
    
    if [ -z "$new_bg_id" ]; then
      local old_bg_name=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -c "SELECT name FROM broker_group WHERE id = $bg_id;" 2>/dev/null | sed 's/^\s*//;s/\s*$//')
      
      # 处理 "(Old)" broker group：尝试映射到非 "(Old)" 版本
      if echo "$old_bg_name" | grep -qi "(Old)"; then
        local non_old_name=$(echo "$old_bg_name" | sed 's/(Old)//gi' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        new_bg_id=$(find_existing_broker_group "$non_old_name" "" 2>/dev/null || echo "")
        if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
          # 尝试更宽松的匹配：去除所有空格后比较
          local non_old_clean=$(echo "$non_old_name" | tr -d ' ')
          local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
          new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\")) == \"$non_old_clean\") | .id" 2>/dev/null | head -1)
        fi
        if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ]; then
          echo_info "Broker $oid ($name): 将 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id ($non_old_name)"
          echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
        else
          echo_warn "跳过 broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
          echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
          echo_warn "  尝试查找非 (Old) 版本: $non_old_name（未找到）"
          [ -n "$existing_in_new" ] && echo_warn "  新系统中已存在同名 broker (ID: $existing_in_new)"
          echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log"
          ((sk++)); continue
        fi
      else
        # 处理其他情况，如 "(Mentee)" 后缀，映射到 "(standard)" 版本
        if echo "$old_bg_name" | grep -qi "(Mentee)"; then
          local standard_name=$(echo "$old_bg_name" | sed 's/(Mentee)/(standard)/gi' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          new_bg_id=$(find_existing_broker_group "$standard_name" "" 2>/dev/null || echo "")
          if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
            # 尝试去除后缀，查找基础名称
            local base_name=$(echo "$old_bg_name" | sed 's/(Mentee)//gi' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            new_bg_id=$(find_existing_broker_group "$base_name" "" 2>/dev/null || echo "")
          fi
          if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
            # 尝试更宽松的匹配：去除所有空格后比较
            local standard_clean=$(echo "$standard_name" | tr -d ' ')
            local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
            new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\")) == \"$standard_clean\") | .id" 2>/dev/null | head -1)
          fi
          if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ]; then
            echo_info "Broker $oid ($name): 将 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id ($standard_name)"
            echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
          else
            echo_warn "跳过 broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
            echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
            echo_warn "  尝试查找 (standard) 版本: $standard_name（未找到）"
            [ -n "$existing_in_new" ] && echo_warn "  新系统中已存在同名 broker (ID: $existing_in_new)"
            echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log"
            ((sk++)); continue
          fi
        else
          # 对于其他情况，也尝试通过名称查找
          new_bg_id=$(find_existing_broker_group "$old_bg_name" "" 2>/dev/null || echo "")
          if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
            # 特殊处理：如果名称是 "EFS ADVISORS PTY LTD"，确保能找到正确的 broker group
            if echo "$old_bg_name" | grep -qi "EFS ADVISORS PTY LTD" && ! echo "$old_bg_name" | grep -qi "(Old)"; then
              local efs_name="EFS ADVISORS PTY LTD"
              new_bg_id=$(find_existing_broker_group "$efs_name" "" 2>/dev/null || echo "")
              if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ]; then
                echo_info "Broker $oid ($name): 将 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id ($efs_name)"
                echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
              else
                echo_warn "跳过 broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
                echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
                echo_warn "  尝试查找: $efs_name（未找到，可能需要先迁移该 broker group）"
                [ -n "$existing_in_new" ] && echo_warn "  新系统中已存在同名 broker (ID: $existing_in_new)"
                echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log"
                ((sk++)); continue
              fi
            else
              echo_warn "跳过 broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
              [ -n "$old_bg_name" ] && echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
              [ -n "$existing_in_new" ] && echo_warn "  新系统中已存在同名 broker (ID: $existing_in_new)"
              echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log"
              ((sk++)); continue
            fi
          else
            echo_info "Broker $oid ($name): 通过名称找到 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id"
            echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
          fi
        fi
      fi
    fi
    # 检查是否通过硬编码映射找到 broker group（使用之前设置的 is_special_broker 标志）
    local is_hardcoded_mapping=$is_special_broker
    
    # 对于特殊 broker，验证 new_bg_id 是否有效
    if [ "$is_special_broker" = "true" ]; then
      if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ] || [ "$new_bg_id" = "" ]; then
        echo_error "Broker $oid ($name): 硬编码映射失败 - new_bg_id 为空或无效"
        echo "SKIP_HARDCODED_MAPPING_FAILED|$oid|$name|$bg_id||新系统ID:$existing_in_new" >> "$skipped_log"
        ((sk++)); continue
      else
        # 验证 broker group 是否真的存在
        local bg_exists=$(echo "$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)" | jq -r ".data.companies[] | select(.id == $new_bg_id) | .id" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$bg_exists" = "0" ] || [ -z "$bg_exists" ]; then
          echo_error "Broker $oid ($name): 硬编码映射的 broker group (ID: $new_bg_id) 不存在于数据库中"
          echo "SKIP_BG_NOT_EXISTS|$oid|$name|$bg_id|$new_bg_id|新系统ID:$existing_in_new" >> "$skipped_log"
          ((sk++)); continue
        else
          echo_info "Broker $oid ($name): 验证通过 - broker group (ID: $new_bg_id) 存在于数据库中"
        fi
      fi
    fi
    
    # 校验本地 DB 的 aggregator 绑定
    if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ] || [ "$new_bg_id" = "" ]; then
      echo_error "Broker $oid ($name): 无法找到 broker_group_id 映射"
      echo "SKIP_BG_NOT_FOUND|$oid|$name|$bg_id||新系统ID:$existing_in_new" >> "$skipped_log"
      ((sk++)); continue
    fi
    
    
    # 生产环境：aggregator 绑定验证将通过 fix.sh prod 完成
    # 跳过直接数据库验证，继续迁移 broker
    local json=$(jq -n --arg email "$email" --arg name "$name" --arg type "NON_DIRECT_PAYMENT" --arg crn "$crn" --argjson broker_group_id "$new_bg_id" --argjson infinity_id "${inf_id:-null}" '{email:$email,name:$name,type:$type,crn:$crn,brokerGroupId:$broker_group_id} + (if $infinity_id != "null" and $infinity_id != "0" and $infinity_id != "" then {infinityId: ($infinity_id | tonumber)} else {} end)')
    local resp=$(call_api POST "/broker" "$json"); local code=$(echo "$resp" | jq -r '.code // "unknown"'); local nid=$(echo "$resp" | jq -r '.data.brokers[0].id // .data.id // .id // empty')
    
    # 对于特殊 broker，输出详细的响应信息
    if [ "$is_special_broker" = "true" ]; then
      echo_info "Broker $oid ($name): API 响应 - code: $code, new_id: $nid"
      if [ "$code" != "0" ] || [ -z "$nid" ] || [ "$nid" = "null" ]; then
        echo_warn "Broker $oid ($name): API 响应详情: $resp"
      fi
    fi
    
    if [ "$code" = "0" ] && [ -n "$nid" ] && [ "$nid" != "null" ]; then
      echo_success "Broker $oid -> $nid: $name"
      # 生产环境：created_at 修复将通过 fix.sh prod 完成
      ((ok++))
    elif echo "$resp" | grep -qi "already exists\|duplicate" || [ "$code" = "10100005" ] || [ "$code" = "2" ]; then
      if [ "$is_special_broker" = "true" ]; then
        echo_info "Broker $oid ($name): 已存在，跳过（可能之前已迁移）"
      fi
      ((sk++))
    else echo_error "Broker $oid 迁移失败: $name"; echo "  响应: $resp"; ((fl++)); fi
  done < "$CSV1"
  echo_info "NON_DIRECT 完成: 成功 $ok, 跳过 $sk, 失败 $fl"
  
  # 显示被跳过的 broker 详情（用于诊断）
  if [ -s "$skipped_log" ] && [ "$sk" -gt 0 ]; then
    echo ""
    echo_warn "被跳过的 Broker 详情（共 $sk 个）:"
    local skip_count=0
    while IFS='|' read -r reason old_id broker_name bg_id bg_name new_id_info || [ -n "$reason" ]; do
      [ -z "$reason" ] && continue
      ((skip_count++))
      if [ "$skip_count" -le 10 ]; then
        echo_warn "  [$skip_count] Broker ID $old_id: $broker_name"
        case "$reason" in
          SKIP_EMPTY_NAME)
            echo "     原因: name 为空"
            ;;
          SKIP_NO_BG_MAPPING)
            echo "     原因: 无法找到 broker_group_id $bg_id 的映射"
            [ -n "$bg_name" ] && echo "     老系统 Broker Group: $bg_name (ID: $bg_id)"
            [ -n "$new_id_info" ] && echo "     $new_id_info"
            ;;
          SKIP_BG_NOT_FOUND)
            echo "     原因: Broker Group 在新系统中不存在"
            [ -n "$bg_name" ] && echo "     老系统 Broker Group: $bg_name (ID: $bg_id)"
            [ -n "$new_id_info" ] && echo "     $new_id_info"
            ;;
        esac
      fi
    done < "$skipped_log"
    if [ "$skip_count" -gt 10 ]; then
      echo_warn "  ... 还有 $((skip_count - 10)) 个被跳过的 broker（详见日志: $skipped_log）"
    fi
    echo ""
    echo_info "提示: 如需查看所有被跳过的 broker，请检查日志文件: $skipped_log"
  fi

  # DIRECT（sub_broker）- 简化版本，移除直接数据库访问
  local CSV2="$TMP2/sub_brokers.csv"; ok=0; sk=0; fl=0
  local skipped_log2="$TMP2/skipped_sub_brokers.log"
  : > "$skipped_log2"
  PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -c "SELECT id, email, name, broker_group_id, infinity_id, bsb_number, account_number, abn, address, phone, deduct, account_name FROM sub_broker WHERE deleted IS NULL" -t -A -F"," > "$CSV2"
  local cnt2=$(wc -l < "$CSV2" | tr -d ' '); echo_info "DIRECT 待迁移: $cnt2"
  while IFS=',' read -r oid email name bg_id inf_id bsb acc_no abn address phone deduct acc_name || [ -n "$oid" ]; do
    [ -z "$oid" ] && continue; oid=$(echo "$oid" | tr -d ' '); name=$(echo "$name" | sed 's/^\s*//;s/\s*$//'); [ -z "$name" ] || [ "$name" = "NULL" ] && { echo "SKIP_EMPTY_NAME|$oid||" >> "$skipped_log2"; ((sk++)); continue; }
    [ -z "$email" ] || [ "$email" = "NULL" ] && { local name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40); email="${name_clean}_${oid}@migrated.local"; }
    local crn=$(get_crn_from_acr "$name"); [ -z "$crn" ] && crn="CRN_SUB_BROKER_${oid}"
    local bsb_clean=$(echo "$bsb" | tr -d -c '0-9'); local account_clean=$(echo "$acc_no" | tr -d -c '0-9')
    
    # 生产环境：跳过直接数据库查询 existing_in_new
    local existing_in_new=""
    
    local new_bg_id=$(grep "^${bg_id}:" "$ID_MAPPING_FILE" | cut -d: -f2 | head -1)
    if [ -z "$new_bg_id" ]; then
      local old_bg_name=$(PGPASSWORD="${OLD_DB_PASS}" psql -h "$OLD_DB_HOST" -p "$OLD_DB_PORT" -U "$OLD_DB_USER" -d "$OLD_DB_NAME" -t -A -c "SELECT name FROM broker_group WHERE id = $bg_id;" 2>/dev/null | sed 's/^\s*//;s/\s*$//')
      
      # 处理 "(Old)" broker group：尝试映射到非 "(Old)" 版本
      if echo "$old_bg_name" | grep -qi "(Old)"; then
        local non_old_name=$(echo "$old_bg_name" | sed 's/(Old)//gi' | sed 's/\s*$//' | sed 's/\s*$//')
        new_bg_id=$(find_existing_broker_group "$non_old_name" "" 2>/dev/null || echo "")
        if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ]; then
          echo_info "Sub-Broker $oid ($name): 将 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id ($non_old_name)"
          echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
        else
          echo_warn "跳过 sub_broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
          echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
          echo_warn "  尝试查找非 (Old) 版本: $non_old_name（未找到）"
          echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log2"
          ((sk++)); continue
        fi
      else
        # 处理其他情况，如 "(Mentee)" 后缀，映射到 "(standard)" 版本
        if echo "$old_bg_name" | grep -qi "(Mentee)"; then
          local standard_name=$(echo "$old_bg_name" | sed 's/(Mentee)/(standard)/gi' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          new_bg_id=$(find_existing_broker_group "$standard_name" "" 2>/dev/null || echo "")
          if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
            local base_name=$(echo "$old_bg_name" | sed 's/(Mentee)//gi' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            new_bg_id=$(find_existing_broker_group "$base_name" "" 2>/dev/null || echo "")
          fi
          if [ -z "$new_bg_id" ] || [ "$new_bg_id" = "null" ]; then
            local standard_clean=$(echo "$standard_name" | tr -d ' ')
            local response=$(call_api GET "/company?type=BROKER_GROUP&size=2000" "" 2>/dev/null)
            new_bg_id=$(echo "$response" | jq -r ".data.companies[] | select((.name | gsub(\" \";\"\")) == \"$standard_clean\") | .id" 2>/dev/null | head -1)
          fi
          if [ -n "$new_bg_id" ] && [ "$new_bg_id" != "null" ]; then
            echo_info "Sub-Broker $oid ($name): 将 broker_group_id $bg_id ($old_bg_name) 映射到 $new_bg_id ($standard_name)"
            echo "$bg_id:$new_bg_id" >> "$ID_MAPPING_FILE"
          else
            echo_warn "跳过 sub_broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
            echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
            echo_warn "  尝试查找 (standard) 版本: $standard_name（未找到）"
            echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log2"
            ((sk++)); continue
          fi
        else
          echo_warn "跳过 sub_broker $oid ($name): 无法找到 broker_group_id $bg_id 的映射"
          [ -n "$old_bg_name" ] && echo_warn "  老系统 Broker Group: $old_bg_name (ID: $bg_id)"
          echo "SKIP_NO_BG_MAPPING|$oid|$name|$bg_id|$old_bg_name|新系统ID:$existing_in_new" >> "$skipped_log2"
          ((sk++)); continue
        fi
      fi
    fi
    # 清理空值
    [ -z "$bsb_clean" ] || [ "$bsb_clean" = "0" ] && bsb_clean=""
    [ -z "$account_clean" ] || [ "$account_clean" = "0" ] && account_clean=""
    [ "$abn" = "NULL" ] && abn=""
    [ "$address" = "NULL" ] && address=""
    [ "$phone" = "NULL" ] && phone=""
    [ "$acc_name" = "NULL" ] && acc_name=""
    
    local json=$(jq -n --arg email "$email" --arg name "$name" --arg type "DIRECT_PAYMENT" --arg crn "$crn" --argjson broker_group_id "$new_bg_id" --arg infinity_id_str "$inf_id" --arg bsb_str "$bsb_clean" --arg account_str "$account_clean" --arg abn "$abn" --arg address "$address" --arg phone "$phone" --arg account_name "$acc_name" '{email:$email,name:$name,type:$type,crn:$crn,brokerGroupId:$broker_group_id} + (if $bsb_str != "" then {bankAccountBsb:$bsb_str} else {} end) + (if $account_str != "" then {bankAccountNumber:$account_str} else {} end) + (if $abn != "" then {abn:$abn} else {} end) + (if $address != "" then {address:$address} else {} end) + (if $phone != "" then {phone:$phone} else {} end) + (if $account_name != "" then {accountName:$account_name} else {} end) + (if $infinity_id_str != "NULL" and $infinity_id_str != "" and $infinity_id_str != "0" then {infinityId: ($infinity_id_str | tonumber)} else {} end)')
    local resp=$(call_api POST "/broker" "$json"); local code=$(echo "$resp" | jq -r '.code // "unknown"'); local nid=$(echo "$resp" | jq -r '.data.brokers[0].id // .data.id // .id // empty')
    if [ "$code" = "0" ] && [ -n "$nid" ] && [ "$nid" != "null" ]; then
      echo_success "Sub-Broker $oid -> $nid: $name"
      # 生产环境：created_at 修复将通过 fix.sh prod 完成
      ((ok++))
    elif echo "$resp" | grep -qi "already exists\|duplicate" || [ "$code" = "10100005" ] || [ "$code" = "2" ]; then 
      echo_warn "Sub-Broker $oid ($name) 已存在或重复，跳过"
      ((sk++))
    else 
      echo_error "Sub-Broker $oid 迁移失败: $name"
      echo_error "  响应: $resp"
      ((fl++))
    fi
  done < "$CSV2"
  echo_info "DIRECT 完成: 成功 $ok, 跳过 $sk, 失败 $fl"
}

# 主流程
migrate_broker_groups
migrate_brokers

echo ""; echo_success "迁移完成，开始修复 created_at/deleted_at（SSH）..."
if "$SCRIPT_DIR/../migrate-to-local/fix.sh" prod; then
  echo_success "生产 created_at/deleted_at 修复完成"
else
  echo_warn "生产修复脚本执行出现问题，请手动运行: ../migrate-to-local/fix.sh prod"
fi

# 清理临时文件（生产环境使用 migrate-to-local 目录的 id_mapping.txt）
if [ -f "$ID_MAPPING_FILE" ]; then
  echo_info "清理临时映射文件: $ID_MAPPING_FILE"
  rm -f "$ID_MAPPING_FILE"
  echo_success "临时文件已清理"
fi

echo ""; echo_success "所有步骤完成！"
