#!/bin/bash
# 生产环境迁移执行脚本
# 使用前请设置环境变量：LOGIN_PASSWORD 和 PROD_DB_PASS

set -e

cd "$(dirname "$0")"
source config.sh

echo "=========================================="
echo "生产环境完整迁移"
echo "=========================================="
echo ""
echo "当前配置："
echo "  API_BASE_URL: $API_BASE_URL"
echo "  LOGIN_EMAIL: ${LOGIN_EMAIL:-未设置}"
echo "  KUBECONFIG_FILE: ${KUBECONFIG_FILE:-未设置}"
echo ""
echo "⚠️  警告：此操作将迁移数据到生产环境！"
echo ""
read -p "确认继续? (yes/no): " confirm
[ "$confirm" = "yes" ] || { echo "已取消"; exit 0; }

echo ""
echo "开始执行迁移..."
./migrate.sh

echo ""
echo "=========================================="
echo "迁移完成！"
echo "=========================================="
