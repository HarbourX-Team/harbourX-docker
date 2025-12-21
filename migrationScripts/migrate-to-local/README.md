# 本地环境迁移

此目录包含用于将数据从老系统迁移到本地 HarbourX 环境的配置和脚本。

## 快速开始

```bash
cd migrate-to-local
source config.sh
./migrate.sh
```

或使用统一入口：

```bash
cd migrationScripts
./migrate.sh local
```

## 配置说明

编辑 `config.sh` 文件以修改配置：

- `LOGIN_EMAIL`: 登录邮箱（需要管理员权限）
- `LOGIN_PASSWORD`: 登录密码
- `API_BASE_URL`: 本地 API 地址（默认: http://localhost:8080/api）

## 迁移步骤

`migrate.sh` 脚本会自动执行以下步骤：

1. 迁移 Broker Groups
2. 迁移 Brokers
3. 修复 created_at 时间戳
