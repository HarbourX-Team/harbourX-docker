#!/bin/bash

# 生产环境迁移配置
# 用于从老系统迁移数据到生产 HarbourX 环境

# API 配置
export API_BASE_URL="http://13.54.207.94/api"

# 登录凭证（使用具有管理员权限的账户）
export LOGIN_EMAIL="${LOGIN_EMAIL:-admin@harbourx.com.au}"
export LOGIN_PASSWORD="${LOGIN_PASSWORD}"

# 老数据库配置（通过 Kubernetes port-forward）
export USE_PORT_FORWARD="true"
export ENVIRONMENT="production"

# 自动发现 kubeconfig（优先使用你提供的 haimoney-infra 目录）
CONNECTION_DIR_DEFAULT="/Users/yafengzhu/Desktop/haimoney/haimoney-infra/connection-file"
if [ -z "$PROD_KUBECONFIG_FILE" ]; then
  if [ -d "$CONNECTION_DIR_DEFAULT" ]; then
    # 优先匹配含 PROD 的 kubeconfig
    PROD_KUBECONFIG_FILE=$(ls -1 "$CONNECTION_DIR_DEFAULT"/*PROD* 2>/dev/null | head -1)
    if [ -z "$PROD_KUBECONFIG_FILE" ]; then
      # 退化匹配任何 kubeconfig 文件
      PROD_KUBECONFIG_FILE=$(ls -1 "$CONNECTION_DIR_DEFAULT"/*kubeconfig*.yaml 2>/dev/null | head -1)
    fi
  fi
fi

# 兼容 KUBECONFIG_FILE（老数据库 port-forward 使用）
if [ -z "$KUBECONFIG_FILE" ]; then
  KUBECONFIG_FILE="$PROD_KUBECONFIG_FILE"
fi

# 如仍未找到，保持为空，由脚本运行时提示错误
export KUBECONFIG_FILE

# 老系统数据库服务名（保持原值，除非你的集群中名称不同）
export KUBERNETES_SERVICE="${KUBERNETES_SERVICE:-broker-db}"
export PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-5434}"

# 数据库连接（port-forward 后）
export OLD_DB_HOST="localhost"
export OLD_DB_PORT="5434"
export OLD_DB_USER="postgres"
export OLD_DB_NAME="broker"
export OLD_DB_PASS="postgres"

# 映射文件
export ID_MAPPING_FILE="migration-report/migrate-prod/id_mapping.txt"
# CRN映射文件在harbourX根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# migrate-to-prod 在 migrationScripts/migrate-to-prod，所以需要回到 migrationScripts 的父目录（harbourX根目录）
HARBOURX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# 确保路径正确（如果计算错误，使用绝对路径）
if [ ! -f "${HARBOURX_ROOT}/acr_crn_mapping.csv" ]; then
    # 尝试从当前目录向上查找
    HARBOURX_ROOT="$(cd "$SCRIPT_DIR" && while [ ! -f "acr_crn_mapping.csv" ] && [ "$(pwd)" != "/" ]; do cd ..; done && pwd)"
fi
export ACR_CRN_MAPPING_FILE="${HARBOURX_ROOT}/acr_crn_mapping.csv"

# 生产数据库配置（用于修复 created_at，可用于 K8S 直连或 SSH 回退）
export PROD_DB_HOST="${PROD_DB_HOST}"
export PROD_DB_PORT="${PROD_DB_PORT:-5432}"
export PROD_DB_USER="${PROD_DB_USER:-postgres}"
export PROD_DB_NAME="${PROD_DB_NAME:-harbourx}"
export PROD_DB_PASS="${PROD_DB_PASS}"

# K8S 修复相关（fix.sh prod 优先使用）
export PROD_KUBECONFIG_FILE
export PROD_DB_SERVICE="${PROD_DB_SERVICE:-harbourx-postgres}"
export PROD_DB_NAMESPACE="${PROD_DB_NAMESPACE:-}"
export PROD_DB_LOCAL_PORT="${PROD_DB_LOCAL_PORT:-6543}"

# SSH 回退参数（如不走 K8S 修复时）
export EC2_HOST
export EC2_USER
export SSH_KEY
export DB_CONTAINER

# 生产服务器 SSH 配置（用于 fix.sh prod）
# 如需通过 SSH 在服务器上修复 created_at/deleted_at，请设置以下变量：
# export EC2_HOST="your-ec2-hostname-or-ip"
# export EC2_USER="ec2-user"  # 或实际用户名
# export SSH_KEY="/absolute/path/to/your-key.pem"
# 也可覆盖容器/数据库参数：
# export DB_CONTAINER="harbourx-postgres"
# export DB_USER="harbourx"
# export DB_NAME="harbourx"
