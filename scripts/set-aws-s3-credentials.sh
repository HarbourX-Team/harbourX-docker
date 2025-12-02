#!/bin/bash

# 设置 AWS S3 凭证脚本
# 用于在 EC2 上设置真实的 AWS S3 凭证

set -e

# 颜色输出
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 设置 AWS S3 凭证${NC}"
echo -e "${BLUE}====================${NC}"
echo ""

# 配置
EC2_HOST="${EC2_HOST:-13.54.207.94}"
EC2_USER="${EC2_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-~/.ssh/harbourX-demo-key-pair.pem}"
SSH_KEY="${SSH_KEY/#\~/$HOME}" # 展开 ~

# 检查是否在本地运行
if [ "$1" = "local" ]; then
    echo -e "${BLUE}在本地设置 AWS S3 凭证...${NC}"
    ENV_FILE="${ENV_FILE:-.env}"
    
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}⚠️  .env 文件不存在，将创建新文件${NC}"
        touch "$ENV_FILE"
    fi
    
    # 读取现有值
    if grep -q "^AWS_S3_ACCESS=" "$ENV_FILE"; then
        CURRENT_ACCESS=$(grep "^AWS_S3_ACCESS=" "$ENV_FILE" | cut -d'=' -f2-)
        echo -e "${YELLOW}当前 AWS_S3_ACCESS: ${CURRENT_ACCESS:0:10}...${NC}"
    fi
    
    # 提示输入
    echo ""
    read -p "请输入 AWS S3 Access Key ID: " AWS_ACCESS_KEY
    read -sp "请输入 AWS S3 Secret Access Key: " AWS_SECRET_KEY
    echo ""
    
    # 更新 .env 文件
    if grep -q "^AWS_S3_ACCESS=" "$ENV_FILE"; then
        sed -i.bak "s|^AWS_S3_ACCESS=.*|AWS_S3_ACCESS=$AWS_ACCESS_KEY|" "$ENV_FILE"
    else
        echo "AWS_S3_ACCESS=$AWS_ACCESS_KEY" >> "$ENV_FILE"
    fi
    
    if grep -q "^AWS_S3_SECRET=" "$ENV_FILE"; then
        sed -i.bak "s|^AWS_S3_SECRET=.*|AWS_S3_SECRET=$AWS_SECRET_KEY|" "$ENV_FILE"
    else
        echo "AWS_S3_SECRET=$AWS_SECRET_KEY" >> "$ENV_FILE"
    fi
    
    echo -e "${GREEN}✅ AWS S3 凭证已更新到 $ENV_FILE${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  注意: 如果后端服务正在运行，需要重启服务以应用新配置${NC}"
    exit 0
fi

# 远程设置（默认）
echo "EC2 主机: $EC2_HOST"
echo "EC2 用户: $EC2_USER"
echo "SSH 密钥: $SSH_KEY"
echo ""

# 检查 SSH 连接
echo -e "${BLUE}1️⃣ 检查 SSH 连接...${NC}"
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}❌ 错误: SSH 密钥文件不存在: $SSH_KEY${NC}"
    exit 1
fi
chmod 400 "$SSH_KEY" 2>/dev/null || true

if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" "echo '连接成功'" > /dev/null 2>&1; then
    echo -e "${RED}❌ 无法连接到 EC2 实例！${NC}"
    exit 1
fi
echo -e "${GREEN}✅ SSH 连接成功${NC}"
echo ""

# 提示输入凭证
echo -e "${BLUE}2️⃣ 输入 AWS S3 凭证${NC}"
read -p "请输入 AWS S3 Access Key ID: " AWS_ACCESS_KEY
read -sp "请输入 AWS S3 Secret Access Key: " AWS_SECRET_KEY
echo ""
echo ""

# 在远程服务器上设置
echo -e "${BLUE}3️⃣ 在 EC2 上设置凭证...${NC}"
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" << EOF
    set -e
    cd /opt/harbourx
    
    # 备份现有 .env 文件
    if [ -f .env ]; then
        cp .env .env.backup.\$(date +%Y%m%d_%H%M%S)
    fi
    
    # 更新或添加 AWS S3 凭证
    if grep -q "^AWS_S3_ACCESS=" .env 2>/dev/null; then
        sed -i.bak "s|^AWS_S3_ACCESS=.*|AWS_S3_ACCESS=$AWS_ACCESS_KEY|" .env
    else
        echo "AWS_S3_ACCESS=$AWS_ACCESS_KEY" >> .env
    fi
    
    if grep -q "^AWS_S3_SECRET=" .env 2>/dev/null; then
        sed -i.bak "s|^AWS_S3_SECRET=.*|AWS_S3_SECRET=$AWS_SECRET_KEY|" .env
    else
        echo "AWS_S3_SECRET=$AWS_SECRET_KEY" >> .env
    fi
    
    echo "✅ AWS S3 凭证已更新"
    
    # 验证设置
    echo ""
    echo "当前配置："
    grep "^AWS_S3" .env | sed 's/=.*/=***/' || echo "未找到 AWS_S3 配置"
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ AWS S3 凭证设置成功${NC}"
    echo ""
    echo -e "${BLUE}4️⃣ 重启后端服务以应用新配置...${NC}"
    ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "cd /opt/harbourx && docker-compose restart backend"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 后端服务已重启${NC}"
        echo ""
        echo -e "${YELLOW}⏳ 等待服务启动（约 30 秒）...${NC}"
        sleep 30
        echo ""
        echo -e "${GREEN}✅ 完成！现在可以尝试上传 RCTI 文件了${NC}"
    else
        echo -e "${RED}❌ 重启后端服务失败${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ 设置 AWS S3 凭证失败${NC}"
    exit 1
fi

