#!/bin/bash

# 本地环境迁移配置
# 用于从老系统迁移数据到本地 HarbourX 环境

# API 配置
export API_BASE_URL="http://localhost:8080/api"

# 登录凭证（使用具有管理员权限的账户）
export LOGIN_EMAIL="${LOGIN_EMAIL:-admin@harbourx.com.au}"
export LOGIN_PASSWORD="${LOGIN_PASSWORD:-password}"

# 老数据库配置（通过 Kubernetes port-forward）
export USE_PORT_FORWARD="true"
export ENVIRONMENT="production"
export KUBECONFIG_FILE="../../haimoney/haimoney-infrastructure/connection-file/haimoney-commissions-cluster-PROD-kubeconfig.yaml"
export KUBERNETES_SERVICE="broker-db"
export PORT_FORWARD_PORT="5434"

# 数据库连接（port-forward 后）
export OLD_DB_HOST="localhost"
export OLD_DB_PORT="5434"
export OLD_DB_USER="postgres"
export OLD_DB_NAME="broker"
export OLD_DB_PASS="postgres"

# 映射文件
export ID_MAPPING_FILE="migration-report/migrate-local/id_mapping_local.txt"
# CRN映射文件在harbourX根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# migrate-to-local 在 migrationScripts/migrate-to-local，所以需要回到 migrationScripts 的父目录（harbourX根目录）
# 从 migrationScripts/migrate-to-local 回到 harbourX 根目录
HARBOURX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# 确保路径正确（如果计算错误，使用绝对路径）
if [ ! -f "${HARBOURX_ROOT}/acr_crn_mapping.csv" ]; then
    # 尝试从当前目录向上查找
    HARBOURX_ROOT="$(cd "$SCRIPT_DIR" && while [ ! -f "acr_crn_mapping.csv" ] && [ "$(pwd)" != "/" ]; do cd ..; done && pwd)"
fi
export ACR_CRN_MAPPING_FILE="${HARBOURX_ROOT}/acr_crn_mapping.csv"

# 本地数据库配置（用于修复 created_at）
export LOCAL_DB_HOST="localhost"
export LOCAL_DB_PORT="5432"
export LOCAL_DB_USER="postgres"
export LOCAL_DB_NAME="harbourx"
export LOCAL_DB_PASS="postgres"
