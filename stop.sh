#!/bin/bash
# HarbourX Docker 停止脚本

cd "$(dirname "$0")"
echo "🛑 停止 HarbourX Docker 服务..."

# 首先尝试使用 docker compose down（处理当前项目）
docker compose down --remove-orphans 2>/dev/null

# 检查是否还有 harbourx 相关的容器在运行
RUNNING_CONTAINERS=$(docker ps --filter "name=harbourx" --format "{{.Names}}" 2>/dev/null)

if [ -n "$RUNNING_CONTAINERS" ]; then
    echo ""
    echo "⚠️  检测到仍有容器在运行，正在强制停止..."
    echo "$RUNNING_CONTAINERS" | while read container; do
        echo "   - 停止容器: $container"
        docker stop "$container" 2>/dev/null
        docker rm "$container" 2>/dev/null
    done
fi

# 再次检查
REMAINING=$(docker ps --filter "name=harbourx" --format "{{.Names}}" 2>/dev/null)
if [ -z "$REMAINING" ]; then
    echo ""
    echo "✅ 所有 HarbourX 服务已停止"
else
    echo ""
    echo "⚠️  以下容器仍在运行:"
    echo "$REMAINING"
fi
