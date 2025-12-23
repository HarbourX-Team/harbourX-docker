# 生产环境迁移

此目录包含用于将数据从老系统迁移到生产 HarbourX 环境的配置和脚本。

## ⚠️ 警告

迁移到生产环境前，请确保：

- 已备份现有数据
- 已测试本地环境迁移
- 使用具有管理员权限的账户
- 已确认所有配置正确

## 快速执行

```bash
cd /Users/yafengzhu/Desktop/harbourX/migrationScripts/migrate-to-prod

# 1. 设置密码（必需）
export LOGIN_PASSWORD="your-production-admin-password"
export PROD_DB_PASS="your-production-db-password"

# 2. 执行迁移
source config.sh
./migrate.sh
```

## 详细步骤

### 步骤 1: 进入目录

```bash
cd /Users/yafengzhu/Desktop/harbourX/migrationScripts/migrate-to-prod
```

### 步骤 2: 设置环境变量

```bash
# 必需：生产环境管理员密码
export LOGIN_PASSWORD="your-production-admin-password"

# 必需：生产数据库密码（用于 fix.sh prod 修复 created_at）
export PROD_DB_PASS="your-production-db-password"

# 可选：如果默认邮箱不对
export LOGIN_EMAIL="admin@harbourx.com.au"
```

### 步骤 3: 加载配置

```bash
source config.sh
```

### 步骤 4: 执行迁移

```bash
./migrate.sh
```

脚本会：

1. 要求确认（输入 `yes`）
2. 迁移 Broker Groups（优先迁移特殊 broker groups）
3. 清理错误的 (Old) broker groups
4. 迁移 Brokers（包括硬编码映射的特殊 broker）
5. 迁移 Sub-Brokers (DIRECT)
6. 自动调用 `fix.sh prod` 修复 created_at/deleted_at

## 配置说明

编辑 `config.sh` 文件以修改配置：

- `LOGIN_EMAIL`: 登录邮箱（需要管理员权限）
- `LOGIN_PASSWORD`: 登录密码（必须通过环境变量设置）
- `API_BASE_URL`: 生产 API 地址（默认: http://13.54.207.94/api）

**注意**: 生产环境的 `created_at` 修复通过 SSH 连接到服务器执行，无需配置数据库连接信息。

## 迁移步骤

`migrate.sh`：执行 Broker Groups 与 Brokers 的迁移；如需修复 created_at/deleted_at，请在 `migrate-to-local/` 目录运行 `./fix.sh prod`（通过 SSH 在服务器执行）。

## 注意事项

- 脚本会自动跳过已存在的数据，不会重复创建
- 迁移完成后会自动修复 created_at 为 2000-01-01
- 如果 fix.sh prod 失败，可以手动运行：`cd ../migrate-to-local && ./fix.sh prod`
