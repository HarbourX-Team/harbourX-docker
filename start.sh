#!/bin/bash
# HarbourX Docker 启动脚本

cd "$(dirname "$0")"
echo "🚀 启动 HarbourX Docker 服务..."
docker compose up -d

echo ""
echo "⏳ 等待服务启动..."
sleep 5

echo ""
echo "📊 服务状态："
docker compose ps

echo ""
echo "✅ 启动完成！"
echo ""
echo "📋 访问地址："
echo "  - 前端: http://localhost"
echo "  - 后端: http://localhost:8080"
echo "  - AI模块: http://localhost:3000"
echo ""
echo "📝 查看日志: docker compose logs -f"
