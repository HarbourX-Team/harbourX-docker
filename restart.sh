#!/bin/bash
# HarbourX Docker 重启脚本

cd "$(dirname "$0")"
echo "🔄 重启 HarbourX Docker 服务..."
docker compose restart

echo ""
echo "⏳ 等待服务重启..."
sleep 5

echo ""
echo "📊 服务状态："
docker compose ps

echo ""
echo "✅ 重启完成！"
