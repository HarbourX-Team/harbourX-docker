# 生产环境迁移

此目录包含用于将数据从老系统迁移到生产 HarbourX 环境的配置和脚本。

## ⚠️ 警告

迁移到生产环境前，请确保：

- 已备份现有数据
- 已测试本地环境迁移
- 使用具有管理员权限的账户
- 已确认所有配置正确

## 快速开始

```bash
cd migrate-to-prod

# 设置生产环境密码（必须）
export LOGIN_PASSWORD="your-admin-password"

# 加载配置并执行迁移
source config.sh
./migrate.sh
```

或使用统一入口：

```bash
cd migrationScripts
export LOGIN_PASSWORD="your-admin-password"
./migrate.sh prod
```

## 配置说明

编辑 `config.sh` 文件以修改配置：

- `LOGIN_EMAIL`: 登录邮箱（需要管理员权限）
- `LOGIN_PASSWORD`: 登录密码（必须通过环境变量设置）
- `API_BASE_URL`: 生产 API 地址（默认: http://13.54.207.94/api）

**注意**: 生产环境的 `created_at` 修复通过 SSH 连接到服务器执行，无需配置数据库连接信息。

## 迁移步骤

`migrate.sh` 脚本会自动执行以下步骤：

1. 迁移 Broker Groups
2. 迁移 Brokers
3. 修复 created_at 时间戳（通过 SSH 连接到生产服务器）
