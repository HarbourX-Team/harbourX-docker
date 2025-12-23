# 本地环境迁移

此目录包含用于将数据从老系统迁移到本地 HarbourX 环境的配置和脚本。

## 快速开始

```bash
cd migrate-to-local
source config.sh
./migrate.sh
```

修复（如遇 MISSING\_\* 错误或计算后需要修复 created_at/deleted_at）：

```bash
./fix.sh
```

## 配置说明

编辑 `config.sh` 文件以修改配置：

- `LOGIN_EMAIL`: 登录邮箱（需要管理员权限）
- `LOGIN_PASSWORD`: 登录密码
- `API_BASE_URL`: 本地 API 地址（默认: http://localhost:8080/api）

## 迁移步骤

`migrate.sh` 脚本会自动执行以下步骤：

1. 迁移 Broker Groups（自动处理 Aggregator 关联并保存映射）
2. 迁移 Brokers（自动修复无法找到 Broker Group 的情况并重试）
3. 如有需要，运行 fix.sh 修复 created_at/deleted_at（避免 MISSING_BROKER_GROUP/MISSING_AGGREGATOR）

## 计算后修复（常见问题）

当上传 RCTI 并计算后，新创建的绑定可能使用"当前时间"作为 created_at，晚于历史 `settled_date + 12h`，从而导致查询出错。

修复说明：fix.sh 会将绑定的 created_at 设置为"最早 settled_date 的次日 12:00（悉尼时区）之前"，并清理不合理的 deleted_at。
