# 云端 AWS S3 配置指南

本文档说明如何在云端（EC2 生产环境）配置 AWS S3 凭证。

## 方法一：通过 .env 文件配置（推荐）

### 步骤 1：SSH 连接到 EC2 实例

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-ip
```

### 步骤 2：进入项目目录

```bash
cd /opt/harbourx
```

### 步骤 3：创建或编辑 .env 文件

```bash
# 如果 .env 文件不存在，先创建
cat > .env << 'EOF'
# Project directory paths
PROJECT_ROOT=..
BACKEND_DIR=HarbourX-Backend
FRONTEND_DIR=HarbourX-Frontend
AI_MODULE_DIR=AI-Module

# Database Configuration
POSTGRES_DB=harbourx
POSTGRES_USER=harbourx
POSTGRES_PASSWORD=your_secure_password
DB_PORT=5432

# JWT Secret
JWT_SECRET=your-super-secret-jwt-key-change-this

# Frontend Allowed Origins
FRONTEND_ALLOWED_ORIGINS=http://your-ec2-ip,http://localhost:3001,http://localhost:80,http://frontend:80

# AWS S3 Configuration
AWS_S3_ACCESS=YOUR_AWS_ACCESS_KEY_ID
AWS_S3_SECRET=YOUR_AWS_SECRET_ACCESS_KEY
EOF
```

**或者如果 .env 文件已存在，只需添加 S3 配置：**

```bash
# 检查是否已有 AWS_S3 配置
grep -q "^AWS_S3_ACCESS=" .env && echo "S3 配置已存在" || {
    echo "" >> .env
    echo "# AWS S3 Configuration" >> .env
    echo "AWS_S3_ACCESS=YOUR_AWS_ACCESS_KEY_ID" >> .env
    echo "AWS_S3_SECRET=YOUR_AWS_SECRET_ACCESS_KEY" >> .env
}
```

### 步骤 4：设置文件权限（安全重要）

```bash
# 确保 .env 文件只有所有者可读写
chmod 600 .env
```

### 步骤 5：重启服务使配置生效

```bash
# 重启后端服务
docker-compose restart backend

# 或者重启所有服务
docker-compose down
docker-compose up -d
```

---

## 方法二：通过环境变量配置

### 在 EC2 上设置系统环境变量

```bash
# 编辑 ~/.bashrc 或 ~/.bash_profile
nano ~/.bashrc

# 添加以下内容
export AWS_S3_ACCESS=YOUR_AWS_ACCESS_KEY_ID
export AWS_S3_SECRET=YOUR_AWS_SECRET_ACCESS_KEY

# 使环境变量生效
source ~/.bashrc
```

### 在 docker-compose.yml 中使用环境变量

`docker-compose.yml` 已经配置为从环境变量读取：

```yaml
environment:
  - AWS_S3_ACCESS=${AWS_S3_ACCESS:-PLACEHOLDER_ACCESS_KEY}
  - AWS_S3_SECRET=${AWS_S3_SECRET:-PLACEHOLDER_SECRET_KEY}
```

重启服务：

```bash
docker-compose restart backend
```

---

## 方法三：通过 harbourx.sh 脚本配置

部署脚本 `harbourx.sh` 支持交互式配置 S3 凭证：

```bash
cd /opt/harbourx

# 运行配置命令（会提示输入 S3 凭证）
./harbourx.sh config env
```

脚本会自动：
1. 检查 `.env` 文件中的现有配置
2. 如果配置无效或缺失，会提示输入
3. 将配置保存到 `.env` 文件

---

## 验证配置

### 方法 1：检查环境变量

```bash
# 在容器内检查
docker-compose exec backend env | grep AWS_S3
```

应该看到：
```
AWS_S3_ACCESS=YOUR_AWS_ACCESS_KEY_ID
AWS_S3_SECRET=YOUR_AWS_SECRET_ACCESS_KEY
```

### 方法 2：检查应用日志

```bash
# 查看后端日志
docker-compose logs backend | grep -i s3

# 或者实时查看
docker-compose logs -f backend
```

### 方法 3：测试 API 端点

```bash
# 测试列出原始文件（需要有效的 JWT token）
curl -X GET "http://localhost:8080/api/commission/transaction/original/list/1" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

如果配置正确，应该返回文件列表或空数组 `{"absolutePaths": []}`，而不是 500 错误。

---

## 安全最佳实践

### 1. 文件权限

```bash
# .env 文件应该只有所有者可读写
chmod 600 .env

# 确保 .env 在 .gitignore 中（不应该提交到 Git）
echo ".env" >> .gitignore
```

### 2. 使用 IAM 角色（推荐用于 EC2）

如果 EC2 实例在 AWS 中运行，最佳实践是使用 IAM 角色而不是访问密钥：

1. 在 EC2 控制台创建 IAM 角色
2. 授予角色 S3 访问权限
3. 将角色附加到 EC2 实例
4. 应用会自动使用实例角色，无需配置访问密钥

**如果使用 IAM 角色，可以删除 .env 中的 AWS_S3_ACCESS 和 AWS_S3_SECRET**

### 3. 限制 S3 访问权限

创建 IAM 用户时，只授予必要的 S3 权限：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::harbourx-rcti",
        "arn:aws:s3:::harbourx-rcti/*"
      ]
    }
  ]
}
```

### 4. 定期轮换访问密钥

- 定期更换访问密钥（建议每 90 天）
- 删除不再使用的访问密钥
- 使用 AWS Secrets Manager 管理密钥（高级选项）

---

## 故障排查

### 问题 1：仍然出现 "AWS Access Key Id you provided does not exist"

**可能原因：**
- 环境变量未正确加载
- .env 文件格式错误
- 容器未重启

**解决方法：**
```bash
# 1. 检查 .env 文件内容
cat .env | grep AWS_S3

# 2. 检查容器环境变量
docker-compose exec backend env | grep AWS_S3

# 3. 重启容器
docker-compose restart backend

# 4. 查看日志
docker-compose logs backend | tail -50
```

### 问题 2：权限被拒绝 (403 Forbidden)

**可能原因：**
- 访问密钥无效
- IAM 用户没有 S3 权限
- Bucket 名称错误

**解决方法：**
1. 在 AWS Console 验证访问密钥是否有效
2. 检查 IAM 用户权限
3. 验证 bucket 名称：`harbourx-rcti`

### 问题 3：配置不生效

**解决方法：**
```bash
# 完全重启所有服务
docker-compose down
docker-compose up -d

# 检查容器状态
docker-compose ps

# 查看详细日志
docker-compose logs backend
```

---

## 当前配置的凭证

**Access Key ID**: `YOUR_AWS_ACCESS_KEY_ID`  
**Secret Access Key**: `YOUR_AWS_SECRET_ACCESS_KEY`  
**Region**: `ap-southeast-2` (Sydney)  
**Bucket**: `harbourx-rcti`

---

## 相关文件

- `docker-compose.yml` - 生产环境配置
- `docker-compose.dev.yml` - 开发环境配置
- `.env` - 环境变量文件（不提交到 Git）
- `harbourx.sh` - 部署脚本（支持交互式配置）

