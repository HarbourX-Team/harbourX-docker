# 数据迁移工具

统一的数据迁移工具，支持本地和生产环境的完整迁移流程。

## 快速开始

### 本地环境

**重要：首次使用前，请将 Kubernetes kubeconfig 文件放置到 `migrationScripts` 目录下**

1. 将 `haimoney-commissions-cluster-PROD-kubeconfig.yaml` 文件复制到 `migrationScripts/` 目录
2. 执行迁移：

```bash
cd migrate-to-local
source config.sh
./migrate.sh
```

### 生产环境

```bash
cd migrate-to-prod

# 设置必需的环境变量
export LOGIN_PASSWORD="your-production-admin-password"
export PROD_DB_PASS="your-production-db-password"

# 加载配置并执行迁移
source config.sh
./migrate.sh
```

## 目录结构

```
migrationScripts/
├── migrate-to-local/     # 本地环境脚本（migrate.sh / fix.sh）
└── migrate-to-prod/      # 生产环境脚本（migrate.sh / fix.sh）
```

## 核心脚本说明

所有脚本已内聚到两个子目录中，每个目录只保留：

- `migrate.sh`：一键迁移（包含 Broker Groups 与 Brokers）
- `fix.sh`：一键修复 created_at/deleted_at
- `config.sh`：环境配置

## 使用流程

### 本地迁移

```bash
cd migrate-to-local
source config.sh
./migrate.sh
# 如需要修复 created_at
./fix.sh
```

### 生产迁移

```bash
cd migrate-to-prod
source config.sh
export LOGIN_PASSWORD='your-password'
export PROD_DB_PASS='your-db-password'
./migrate.sh
# 如需要修复 created_at（通过 SSH 在服务器执行）
cd ../migrate-to-local
./fix.sh prod
```

## 环境变量

### 本地环境

在 `migrate-to-local/config.sh` 中配置：

- `API_BASE_URL`: API 地址（默认: `http://localhost:8080/api`）
- `LOGIN_EMAIL`: 登录邮箱
- `LOGIN_PASSWORD`: 登录密码
- `LOCAL_DB_*`: 本地数据库配置

**Kubernetes kubeconfig 文件配置：**

- 将 `haimoney-commissions-cluster-PROD-kubeconfig.yaml` 文件放置到 `migrationScripts/` 目录下
- 该文件用于通过 Kubernetes port-forward 连接到生产数据库
- 该文件已被 `.gitignore` 忽略，不会提交到版本控制

### 生产环境

在 `migrate-to-prod/config.sh` 中配置：

- `API_BASE_URL`: API 地址（默认: `http://13.54.207.94/api`）
- `LOGIN_EMAIL`: 登录邮箱（默认: `admin@harbourx.com.au`）
- `LOGIN_PASSWORD`: 登录密码（**必须通过环境变量设置**）
- `PROD_DB_PASS`: 生产数据库密码（**必须通过环境变量设置**，用于 fix.sh）

**注意**: 生产环境的 `created_at` 修复通过 SSH 连接到服务器执行，无需配置数据库连接信息。

## 故障排除

### Kubeconfig 文件未找到

如果遇到 kubeconfig 文件未找到的错误：

1. 确认 `haimoney-commissions-cluster-PROD-kubeconfig.yaml` 文件已放置在 `migrationScripts/` 目录下
2. 检查文件权限，确保脚本有读取权限
3. 验证文件路径是否正确（脚本会自动从 `migrationScripts/` 目录查找）

### MISSING_BROKER_GROUP / MISSING_AGGREGATOR

大多由 created_at 时间戳晚于 loan 的 `settled_date + 12h` 引起。

- 本地：`cd migrate-to-local && ./fix.sh`
- 生产：`cd migrate-to-local && ./fix.sh prod`

### 权限错误 (12110001)

如果遇到权限错误，检查：

1. Broker Group ID 映射是否正确
2. Broker Group 是否已正确关联到 Aggregator
3. 本地脚本会在迁移后自动修复 Broker Groups 与 Aggregator 的绑定

### 迁移失败

1. 检查网络连接和 API 地址
2. 验证登录凭据
3. 检查数据库连接
4. 查看脚本输出的详细错误信息

### 生产环境迁移问题

- 如果只迁移了少量 brokers（如 18 个），检查：
  - CSV 分隔符是否正确（应使用管道符 `|`）
  - Broker 数量检测逻辑是否正常工作
  - 强制迁移逻辑是否在 broker 数量 < 50 时生效
- 查看迁移日志文件了解详细错误信息
