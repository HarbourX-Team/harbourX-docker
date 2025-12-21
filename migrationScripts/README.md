# 数据迁移工具

统一的数据迁移工具，支持本地和生产环境的完整迁移流程。

## 快速开始

### 统一入口脚本

使用 `migrate.sh` 作为统一入口：

```bash
# 查看帮助
./migrate.sh help

# 迁移到本地环境
./migrate.sh local

# 迁移到生产环境
./migrate.sh prod

# 清理本地数据库
./migrate.sh clean-local

# 验证本地数据
./migrate.sh verify-local

# 验证生产数据
./migrate.sh verify-prod
```

## 目录结构

```
migrationScripts/
├── migrate.sh                          # 统一入口脚本
├── migrate-broker-groups.sh            # 迁移 Broker Groups
├── migrate-brokers.sh                  # 迁移 Brokers
├── fix-local-created-at.sh             # 修复本地 created_at
├── fix-prod-created-at-via-ssh.sh     # 修复生产 created_at（通过SSH）
├── diagnose-prod-missing-aggregator.sh # 诊断生产环境错误
├── verify-created-at.sh                # 验证 created_at
├── verify-relationships.sh              # 验证关系绑定
├── clean-local-database.sh             # 清理本地数据库
├── FIX_AFTER_CALCULATION.md           # 计算后修复说明
├── migrate-to-local/                   # 本地环境配置
│   ├── config.sh
│   ├── migrate.sh
│   └── README.md
└── migrate-to-prod/                    # 生产环境配置
    ├── config.sh
    ├── migrate.sh
    └── README.md
```

## 核心脚本说明

### 迁移脚本

- **migrate-broker-groups.sh**: 迁移 Broker Groups，自动处理 ID 映射和去重
- **migrate-brokers.sh**: 迁移 Brokers，自动处理权限错误和映射修复

### 修复脚本

- **fix-local-created-at.sh**: 修复本地数据库的 `created_at` 时间戳问题
- **fix-prod-created-at-via-ssh.sh**: 通过 SSH 修复生产数据库的 `created_at` 时间戳问题

### 诊断脚本

- **diagnose-prod-missing-aggregator.sh**: 诊断生产环境的 `MISSING_AGGREGATOR` 错误

### 验证脚本

- **verify-created-at.sh**: 验证 `created_at` 修复状态
- **verify-relationships.sh**: 验证并自动修复关系绑定

### 工具脚本

- **clean-local-database.sh**: 清理本地数据库中的所有迁移数据

## 使用流程

### 本地迁移

```bash
# 1. 清理本地数据库（可选）
./migrate.sh clean-local

# 2. 执行迁移
./migrate.sh local

# 3. 验证数据
./migrate.sh verify-local
```

### 生产迁移

```bash
# 1. 设置生产环境密码
export LOGIN_PASSWORD='your-password'

# 2. 执行迁移
./migrate.sh prod

# 3. 验证数据
./migrate.sh verify-prod
```

## 环境变量

### 本地环境

在 `migrate-to-local/config.sh` 中配置：

- `API_BASE_URL`: API 地址（默认: `http://localhost:8080/api`）
- `LOGIN_EMAIL`: 登录邮箱
- `LOGIN_PASSWORD`: 登录密码
- `LOCAL_DB_*`: 本地数据库配置

### 生产环境

在 `migrate-to-prod/config.sh` 中配置：

- `API_BASE_URL`: API 地址
- `LOGIN_EMAIL`: 登录邮箱
- `LOGIN_PASSWORD`: 登录密码（必须设置）

**注意**: 生产环境的 `created_at` 修复通过 SSH 连接到服务器执行，无需配置数据库连接信息。

## 故障排除

### MISSING_BROKER_GROUP / MISSING_AGGREGATOR

这些错误通常由 `created_at` 时间戳问题引起：

**本地环境**:

```bash
./fix-local-created-at.sh
```

**生产环境**:

```bash
./fix-prod-created-at-via-ssh.sh
```

**重要提示**: 如果在上传 RCTI 文件并计算后出现这些错误，需要在计算完成后运行修复脚本。详细说明请查看 `FIX_AFTER_CALCULATION.md`。

### 权限错误 (12110001)

如果遇到权限错误，检查：

1. Broker Group ID 映射是否正确
2. Broker Group 是否已正确关联到 Aggregator
3. 使用 `verify-relationships.sh` 自动修复关系

### 迁移失败

1. 检查网络连接和 API 地址
2. 验证登录凭据
3. 检查数据库连接
4. 查看脚本输出的详细错误信息
