# 数据迁移完整指南

## 概述

本指南包含从旧系统（HaiMoney）迁移数据到新系统（HarbourX）的完整说明，包括数据结构对应关系、字段映射、迁移步骤、常见问题等。

## 目录

1. [快速开始](#快速开始)
2. [数据结构对应关系](#数据结构对应关系)
   - [Broker Group 数据结构](#broker-group-数据结构)
   - [Broker 数据结构](#broker-数据结构)
   - [Fee Model 数据结构](#fee-model-数据结构)
   - [Commission Model 数据结构](#commission-model-数据结构)
   - [Client 数据结构](#client-数据结构)
   - [Loan 数据结构](#loan-数据结构)
3. [迁移步骤](#迁移步骤)
4. [数据映射关系](#数据映射关系)
5. [迁移注意事项](#迁移注意事项)
6. [常见问题](#常见问题)
7. [API 端点参考](#api-端点参考)

---

## 快速开始

```bash
# 1. 设置环境变量
export OLD_DB_PASS="your_password"
export API_BASE_URL="http://13.54.207.94/api"  # 或 http://localhost:8080/api

# 2. 选择环境（staging 或 production）
export ENVIRONMENT="staging"  # 默认是 staging
# 或
export ENVIRONMENT="production"  # 使用生产环境

# 3. 运行完整迁移（先迁移 Broker Groups，再迁移 Brokers）
./migrate-all.sh

# 4. 如果需要先清理云端数据
./migrate-all.sh --clean

# 5. 或者使用独立的清理脚本
./clean-cloud-data.sh
```

**注意**:

- 默认连接 **staging** 环境
- 生产环境有 144 个 Broker Groups，staging 环境有 120 个
- 要迁移生产环境数据，必须设置 `ENVIRONMENT=production`

---

## 数据结构对应关系

### Broker Group 数据结构

#### 老系统（HaiMoney）表结构

**表名**: `broker_group` (注意：老系统实际使用 `broker_group` 表，不是 `companies`)

| 字段名           | 类型      | 说明                        | 是否必需 |
| ---------------- | --------- | --------------------------- | -------- |
| `id`             | BIGINT    | 主键 ID                     | ✅       |
| `name`           | VARCHAR   | 公司名称                    | ✅       |
| `abn`            | VARCHAR   | ABN 号码                    | ✅       |
| `account_name`   | VARCHAR   | 银行账户名称                | ✅       |
| `bsb_number`     | VARCHAR   | BSB 号码                    | ✅       |
| `account_number` | VARCHAR   | 银行账户号码                | ✅       |
| `email`          | VARCHAR   | 邮箱（可选）                | ❌       |
| `phone`          | VARCHAR   | 电话（可选）                | ❌       |
| `address`        | VARCHAR   | 地址（可选）                | ❌       |
| `deleted`        | TIMESTAMP | 删除时间（NULL 表示未删除） | -        |

**查询示例**:

```sql
SELECT id, name, abn, account_name, bsb_number, account_number,
       email, phone, address
FROM broker_group
WHERE deleted IS NULL;
```

#### 新系统（HarbourX）表结构

**表名**: `companies` (type = 2 表示 BROKER_GROUP)

| 字段名                | 类型      | 说明                       | 是否必需 |
| --------------------- | --------- | -------------------------- | -------- |
| `id`                  | BIGINT    | 主键 ID                    | ✅       |
| `type`                | SMALLINT  | 公司类型，2 = BROKER_GROUP | ✅       |
| `name`                | VARCHAR   | 公司名称（唯一）           | ✅       |
| `abn`                 | BIGINT    | ABN 号码（唯一）           | ✅       |
| `bank_account_name`   | VARCHAR   | 银行账户名称               | ✅       |
| `bank_account_bsb`    | INTEGER   | BSB 号码                   | ✅       |
| `bank_account_number` | INTEGER   | 银行账户号码               | ✅       |
| `acl`                 | VARCHAR   | ACL 权限（可选）           | ❌       |
| `extra_info`          | JSONB     | 额外信息（JSON）           | ❌       |
| `created_at`          | TIMESTAMP | 创建时间                   | ✅       |
| `updated_at`          | TIMESTAMP | 更新时间                   | ✅       |

**关联表**: `aggregator_broker_groups`

- `aggregator_id`: Aggregator 公司 ID
- `broker_group_id`: Broker Group 公司 ID
- `created_at`: 关联创建时间
- `deleted_at`: 软删除时间（NULL 表示未删除）

#### API 请求结构

**端点**: `POST /api/company/broker-group`

**请求体** (`BrokerGroupRequest`):

```json
{
  "name": "Broker Group Name",
  "abn": 12345678901,
  "bankAccountName": "Bank Account Name",
  "bankAccountBsb": 123456,
  "bankAccountNumber": 12345678,
  "aggregatorCompanyId": 1,
  "email": "email@example.com",
  "phoneNumber": "+61 2 1234 5678",
  "address": "123 Street, City"
}
```

---

### Broker 数据结构

#### 老系统（HaiMoney）表结构

**表名**: `broker` (NON_DIRECT_PAYMENT)

| 字段名            | 类型      | 说明                                  | 是否必需 | 迁移说明          |
| ----------------- | --------- | ------------------------------------- | -------- | ----------------- |
| `id`              | INT       | 主键 ID                               | ✅       | 不迁移，使用新 ID |
| `name`            | STRING    | 名称                                  | ✅       | 直接映射          |
| `broker_group_id` | INT       | Broker Group ID                       | ✅       | 映射到新系统      |
| `sub_broker_id`   | INT       | Sub Broker ID（指向 `sub_broker` 表） | -        | 用于判断类型      |
| `infinity_id`     | INT       | Infinity ID（可选）                   | ❌       | 直接迁移          |
| `deleted`         | TIMESTAMP | 删除时间（NULL 表示未删除）           | -        | 只迁移未删除的    |

**表名**: `sub_broker` (DIRECT_PAYMENT)

| 字段名            | 类型      | 说明                        | 是否必需 | 迁移说明                          |
| ----------------- | --------- | --------------------------- | -------- | --------------------------------- |
| `id`              | INT       | 主键 ID                     | ✅       | 不迁移，使用新 ID                 |
| `name`            | STRING    | 名称                        | ✅       | 直接映射                          |
| `email`           | STRING    | 邮箱（唯一）                | ❌       | 直接迁移                          |
| `broker_group_id` | INT       | Broker Group ID             | ✅       | 映射到新系统                      |
| `abn`             | STRING    | ABN 号码                    | ❌       | 作为直接字段（不放入 extra_info） |
| `address`         | STRING    | 地址                        | ❌       | 作为直接字段（不放入 extra_info） |
| `phone`           | STRING    | 电话                        | ❌       | 作为直接字段（不放入 extra_info） |
| `account_name`    | STRING    | 账户名称                    | ❌       | 作为直接字段（不放入 extra_info） |
| `bsb_number`      | STRING    | BSB 号码                    | ❌       | 直接映射到 bankAccountBsb 字段    |
| `account_number`  | STRING    | 账户号码                    | ❌       | 直接映射到 bankAccountNumber 字段 |
| `infinity_id`     | INT       | Infinity ID（可选）         | ❌       | 直接迁移                          |
| `deduct`          | BOOL      | 是否扣除                    | ✅       | **不迁移**                        |
| `deleted`         | TIMESTAMP | 删除时间（NULL 表示未删除） | -        | 只迁移未删除的                    |

**重要逻辑**:

- **`broker` 表** → 新系统 **`NON_DIRECT_PAYMENT` broker**
  - 使用 `broker.broker_group_id` 映射到新系统的 broker_group_id
  - 从 `broker.name` 生成 email（格式：`{name_clean}_{old_id}@migrated.local`）
  - 从 ACR Register.xlsm 获取 CRN，如果找不到则使用 `CRN_BROKER_{old_id}`
- **`sub_broker` 表** → 新系统 **`DIRECT_PAYMENT` broker**
  - 使用 `sub_broker.broker_group_id` 映射到新系统的 broker_group_id
  - 使用 `sub_broker.email`（如果为空，从 `sub_broker.name` 生成）
  - `bsb_number` 和 `account_number` **直接映射到 `bankAccountBsb` 和 `bankAccountNumber` 字段**
  - `abn`, `address`, `phone`, `account_name` 作为**直接字段**（不是 extra_info）
  - `deduct` **不迁移**
  - 从 ACR Register.xlsm 获取 CRN，如果找不到则使用 `CRN_SUB_BROKER_{old_id}`

#### 新系统（HarbourX）表结构

**表名**: `brokers`

| 字段名                | 类型      | 说明                                                | 是否必需 | 迁移来源                                                                                      |
| --------------------- | --------- | --------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------- |
| `id`                  | BIGINT    | 主键 ID                                             | ✅       | 新生成                                                                                        |
| `name`                | VARCHAR   | Broker 名称                                         | ✅       | `broker.name` 或 `sub_broker.name`                                                            |
| `email`               | VARCHAR   | 邮箱（唯一）                                        | ✅       | `sub_broker.email` 或从 `name` 生成                                                           |
| `type`                | SMALLINT  | Broker 类型：1=DIRECT_PAYMENT, 2=NON_DIRECT_PAYMENT | ✅       | `broker`→NON_DIRECT_PAYMENT, `sub_broker`→DIRECT_PAYMENT                                      |
| `infinity_id`         | BIGINT    | Infinity ID（可选）                                 | ❌       | `broker.infinity_id` 或 `sub_broker.infinity_id`                                              |
| `crn`                 | VARCHAR   | CRN 号码（唯一）                                    | ✅       | 从 ACR Register.xlsm 获取，或生成（格式：`CRN_BROKER_{old_id}` 或 `CRN_SUB_BROKER_{old_id}`） |
| `bank_account_bsb`    | INTEGER   | BSB 号码（可选，仅 DIRECT_PAYMENT）                 | ❌       | `sub_broker.bsb_number`（直接字段）                                                           |
| `bank_account_number` | INTEGER   | 银行账户号码（可选，仅 DIRECT_PAYMENT）             | ❌       | `sub_broker.account_number`（直接字段）                                                       |
| `abn`                 | VARCHAR   | ABN 号码（可选，仅 DIRECT_PAYMENT）                 | ❌       | `sub_broker.abn`（直接字段，存储在 extra_info 中）                                            |
| `address`             | VARCHAR   | 地址（可选，仅 DIRECT_PAYMENT）                     | ❌       | `sub_broker.address`（直接字段，存储在 extra_info 中）                                        |
| `phone`               | VARCHAR   | 电话（可选，仅 DIRECT_PAYMENT）                     | ❌       | `sub_broker.phone`（直接字段，存储在 extra_info 中）                                          |
| `account_name`        | VARCHAR   | 账户名称（可选，仅 DIRECT_PAYMENT）                 | ❌       | `sub_broker.account_name`（直接字段，存储在 extra_info 中）                                   |
| `extra_info`          | JSONB     | 额外信息（JSON）                                    | ❌       | 包含 `abn`, `address`, `phone`, `accountName` 等                                              |
| `created_at`          | TIMESTAMP | 创建时间                                            | ✅       | 新生成                                                                                        |
| `updated_at`          | TIMESTAMP | 更新时间                                            | ✅       | 新生成                                                                                        |

**关联表**: `broker_group_brokers`

- `broker_group_id`: Broker Group 公司 ID
- `broker_id`: Broker ID
- `created_at`: 关联创建时间
- `deleted_at`: 软删除时间（NULL 表示未删除）

**重要**: 即使是 `DIRECT_PAYMENT` broker，也必须关联到一个 Broker Group（不能为 NULL）

#### API 请求结构

**端点**: `POST /api/broker`

**请求体** (`BrokerRequest`):

**NON_DIRECT_PAYMENT Broker**:

```json
{
  "name": "Broker Name",
  "email": "broker@example.com",
  "type": "NON_DIRECT_PAYMENT",
  "crn": "CRN123456",
  "brokerGroupId": 1,
  "infinityId": 12345
}
```

**DIRECT_PAYMENT Broker**:

```json
{
  "name": "Broker Name",
  "email": "broker@example.com",
  "type": "DIRECT_PAYMENT",
  "crn": "CRN123456",
  "brokerGroupId": 1,
  "infinityId": 12345,
  "bankAccountBsb": 123456,
  "bankAccountNumber": 12345678,
  "abn": "12345678901",
  "address": "123 Street, City",
  "phone": "+61 2 1234 5678",
  "accountName": "Account Name"
}
```

**BrokerType 枚举**:

- `DIRECT_PAYMENT` (typeId = 1)
- `NON_DIRECT_PAYMENT` (typeId = 2)

---

### Fee Model 数据结构

#### 老系统（HaiMoney）表结构

**表名**: `fee_models`

| 字段名        | 类型      | 说明                        | 是否必需 |
| ------------- | --------- | --------------------------- | -------- |
| `id`          | BIGINT    | 主键 ID                     | ✅       |
| `company_id`  | BIGINT    | 公司 ID（Broker Group）     | ✅       |
| `user_id`     | BIGINT    | 用户 ID                     | ✅       |
| `name`        | VARCHAR   | Fee Model 名称              | ✅       |
| `description` | VARCHAR   | 描述（可选）                | ❌       |
| `created_at`  | TIMESTAMP | 创建时间                    | ✅       |
| `updated_at`  | TIMESTAMP | 更新时间                    | ✅       |
| `deleted`     | TIMESTAMP | 删除时间（NULL 表示未删除） | -        |

**表名**: `fee_items`

| 字段名        | 类型             | 说明                                         | 是否必需 |
| ------------- | ---------------- | -------------------------------------------- | -------- |
| `id`          | BIGINT           | 主键 ID                                      | ✅       |
| `model_id`    | BIGINT           | Fee Model ID                                 | ✅       |
| `description` | VARCHAR          | 描述（可选）                                 | ❌       |
| `type`        | SMALLINT         | 类型：1=PER_LOAN, 2=PER_MONTH, 3=WITHHOLDING | ✅       |
| `amount`      | DOUBLE PRECISION | 金额                                         | ✅       |
| `created_at`  | TIMESTAMP        | 创建时间                                     | ✅       |
| `deleted`     | TIMESTAMP        | 删除时间（NULL 表示未删除）                  | -        |

#### 新系统（HarbourX）表结构

**表名**: `fee_models`

| 字段名        | 类型      | 说明                          | 是否必需 |
| ------------- | --------- | ----------------------------- | -------- |
| `id`          | BIGINT    | 主键 ID                       | ✅       |
| `company_id`  | BIGINT    | 公司 ID（Broker Group）       | ✅       |
| `user_id`     | BIGINT    | 用户 ID                       | ✅       |
| `name`        | VARCHAR   | Fee Model 名称                | ✅       |
| `description` | VARCHAR   | 描述（可选）                  | ❌       |
| `created_at`  | TIMESTAMP | 创建时间                      | ✅       |
| `updated_at`  | TIMESTAMP | 更新时间                      | ✅       |
| `deleted_at`  | TIMESTAMP | 软删除时间（NULL 表示未删除） | -        |

**表名**: `fee_model_items`

| 字段名        | 类型             | 说明                                         | 是否必需 |
| ------------- | ---------------- | -------------------------------------------- | -------- |
| `id`          | BIGINT           | 主键 ID                                      | ✅       |
| `model_id`    | BIGINT           | Fee Model ID                                 | ✅       |
| `description` | VARCHAR          | 描述（可选）                                 | ❌       |
| `type`        | SMALLINT         | 类型：1=PER_LOAN, 2=PER_MONTH, 3=WITHHOLDING | ✅       |
| `amount`      | DOUBLE PRECISION | 金额                                         | ✅       |
| `created_at`  | TIMESTAMP        | 创建时间                                     | ✅       |
| `deleted_at`  | TIMESTAMP        | 软删除时间（NULL 表示未删除）                | -        |

---

### Commission Model 数据结构

#### 老系统（HaiMoney）表结构

**表名**: `commission_models`

| 字段名        | 类型      | 说明                        | 是否必需 |
| ------------- | --------- | --------------------------- | -------- |
| `id`          | BIGINT    | 主键 ID                     | ✅       |
| `company_id`  | BIGINT    | 公司 ID（Broker Group）     | ✅       |
| `user_id`     | BIGINT    | 用户 ID                     | ✅       |
| `name`        | VARCHAR   | Commission Model 名称       | ✅       |
| `description` | VARCHAR   | 描述（可选）                | ❌       |
| `created_at`  | TIMESTAMP | 创建时间                    | ✅       |
| `updated_at`  | TIMESTAMP | 更新时间                    | ✅       |
| `deleted`     | TIMESTAMP | 删除时间（NULL 表示未删除） | -        |

**表名**: `commission_items`

| 字段名                   | 类型             | 说明                        | 是否必需 |
| ------------------------ | ---------------- | --------------------------- | -------- |
| `id`                     | BIGINT           | 主键 ID                     | ✅       |
| `model_id`               | BIGINT           | Commission Model ID         | ✅       |
| `description`            | VARCHAR          | 描述（可选）                | ❌       |
| `from_node_binding_type` | SMALLINT         | 源节点绑定类型              | ✅       |
| `from_node_binding_id`   | BIGINT           | 源节点绑定 ID               | ✅       |
| `to_node_binding_type`   | SMALLINT         | 目标节点绑定类型            | ✅       |
| `to_node_binding_id`     | BIGINT           | 目标节点绑定 ID             | ✅       |
| `allocation_type`        | SMALLINT         | 分配类型                    | ✅       |
| `upfront_percentage`     | DOUBLE PRECISION | Upfront 百分比（0-100）     | ✅       |
| `trail_percentage`       | DOUBLE PRECISION | Trail 百分比（0-100）       | ✅       |
| `created_at`             | TIMESTAMP        | 创建时间                    | ✅       |
| `deleted`                | TIMESTAMP        | 删除时间（NULL 表示未删除） | -        |

#### 新系统（HarbourX）表结构

**表名**: `commission_templates`

| 字段名          | 类型      | 说明                          | 是否必需 |
| --------------- | --------- | ----------------------------- | -------- |
| `id`            | BIGINT    | 主键 ID                       | ✅       |
| `company_id`    | BIGINT    | 公司 ID（Broker Group）       | ✅       |
| `user_id`       | BIGINT    | 用户 ID                       | ✅       |
| `template_type` | SMALLINT  | 模板类型（通常为 NORMAL）     | ✅       |
| `name`          | VARCHAR   | Commission Template 名称      | ✅       |
| `description`   | VARCHAR   | 描述（可选）                  | ❌       |
| `created_at`    | TIMESTAMP | 创建时间                      | ✅       |
| `updated_at`    | TIMESTAMP | 更新时间                      | ✅       |
| `deleted_at`    | TIMESTAMP | 软删除时间（NULL 表示未删除） | -        |

**重要**: 新系统使用**树形结构**（`CommissionTemplateNode`）而不是扁平列表。树结构存储在 `commission_template_items` 表中，通过父子关系组织。

**表名**: `commission_template_items` (树形结构)

| 字段名                           | 类型             | 说明                          | 是否必需 |
| -------------------------------- | ---------------- | ----------------------------- | -------- |
| `id`                             | BIGINT           | 主键 ID                       | ✅       |
| `template_id`                    | BIGINT           | Commission Template ID        | ✅       |
| `description`                    | VARCHAR          | 描述（可选）                  | ❌       |
| `from_node_binding_type`         | SMALLINT         | 源节点绑定类型                | ✅       |
| `from_node_binding_id`           | BIGINT           | 源节点绑定 ID                 | ✅       |
| `to_node_binding_type`           | SMALLINT         | 目标节点绑定类型              | ✅       |
| `to_node_binding_id`             | BIGINT           | 目标节点绑定 ID               | ✅       |
| `allocation_type`                | SMALLINT         | 分配类型                      | ✅       |
| `allocation_value_upfront`       | DOUBLE PRECISION | Upfront 分配值（0-1 小数）    | ✅       |
| `allocation_value_trail`         | DOUBLE PRECISION | Trail 分配值（0-1 小数）      | ✅       |
| `allocation_source_binding_type` | SMALLINT         | 分配源绑定类型                | ✅       |
| `allocation_source_binding_id`   | BIGINT           | 分配源绑定 ID                 | ✅       |
| `created_at`                     | TIMESTAMP        | 创建时间                      | ✅       |
| `deleted_at`                     | TIMESTAMP        | 软删除时间（NULL 表示未删除） | -        |

**重要转换**:

- 老系统的 `upfront_percentage` 和 `trail_percentage` 是 0-100 的整数
- 新系统的 `allocationValueUpfront` 和 `allocationValueTrail` 是 0-1 的小数
- 需要将百分比除以 100 进行转换

---

### Client 数据结构

#### 老系统（HaiMoney）表结构

**注意**: 老系统可能没有独立的 `clients` 表，客户信息可能存储在 `loans` 表的 `client_name` 字段中。

#### 新系统（HarbourX）表结构

**表名**: `clients`

| 字段名        | 类型      | 说明      | 是否必需 |
| ------------- | --------- | --------- | -------- |
| `id`          | BIGINT    | 主键 ID   | ✅       |
| `client_name` | VARCHAR   | 客户名称  | ✅       |
| `broker_id`   | BIGINT    | Broker ID | ✅       |
| `created_at`  | TIMESTAMP | 创建时间  | ✅       |
| `updated_at`  | TIMESTAMP | 更新时间  | ✅       |

**关联表**: `loan_applicants` (客户详细信息)

---

### Loan 数据结构

#### 老系统（HaiMoney）表结构

**表名**: `loans`

| 字段名            | 类型             | 说明                        | 是否必需 |
| ----------------- | ---------------- | --------------------------- | -------- |
| `id`              | BIGINT           | 主键 ID                     | ✅       |
| `broker_id`       | BIGINT           | Broker ID                   | ✅       |
| `broker_group_id` | BIGINT           | Broker Group ID             | ✅       |
| `client_name`     | VARCHAR          | 客户名称                    | ✅       |
| `lender_name`     | VARCHAR          | 贷款机构名称                | ❌       |
| `lender_ref`      | VARCHAR          | 贷款机构参考号              | ❌       |
| `settled_date`    | DATE             | 结算日期                    | ❌       |
| `settled_amount`  | DOUBLE PRECISION | 结算金额                    | ❌       |
| `status`          | SMALLINT         | 状态                        | ✅       |
| `created_at`      | TIMESTAMP        | 创建时间                    | ✅       |
| `updated_at`      | TIMESTAMP        | 更新时间                    | ✅       |
| `deleted`         | TIMESTAMP        | 删除时间（NULL 表示未删除） | -        |

#### 新系统（HarbourX）表结构

**表名**: `loans`

| 字段名            | 类型             | 说明                                                 | 是否必需 |
| ----------------- | ---------------- | ---------------------------------------------------- | -------- |
| `id`              | BIGINT           | 主键 ID                                              | ✅       |
| `broker_id`       | BIGINT           | Broker ID                                            | ✅       |
| `broker_group_id` | BIGINT           | Broker Group ID                                      | ✅       |
| `aggregator_id`   | BIGINT           | Aggregator ID                                        | ✅       |
| `client_name`     | VARCHAR          | 客户名称                                             | ✅       |
| `lender_name`     | VARCHAR          | 贷款机构名称                                         | ❌       |
| `lender_ref`      | VARCHAR          | 贷款机构参考号（唯一约束：lender_name + lender_ref） | ❌       |
| `settled_date`    | DATE             | 结算日期                                             | ❌       |
| `settled_amount`  | DOUBLE PRECISION | 结算金额                                             | ❌       |
| `status`          | SMALLINT         | 状态                                                 | ✅       |
| `created_at`      | TIMESTAMP        | 创建时间                                             | ✅       |
| `updated_at`      | TIMESTAMP        | 更新时间                                             | ✅       |

---

## 迁移步骤

### 迁移顺序

1. **Broker Groups** - 必须先迁移，因为 Brokers 依赖它们
2. **Brokers** - 包括 NON_DIRECT_PAYMENT 和 DIRECT_PAYMENT 两种类型
3. **Fee Models**（可选）
4. **Commission Models**（可选）
5. **Clients**（可选）
6. **Loans**（可选）

### Broker Groups 迁移

**脚本**: `migrate-broker-groups.sh`

**功能**:

- 从旧数据库读取 Broker Groups
- 检查是否已存在（通过 ABN 或 name）
- 创建新的 Broker Group
- 保存 ID 映射关系（`id_mapping.txt` 或 `id_mapping_local.txt`）

**字段映射**:

- `name` → `name`
- `abn` → `abn` (用于唯一性检查)
- `email` → `email` (可选)
- `phone` → `phoneNumber` (可选)
- `address` → `address` (可选)

**注意事项**:

- 如果 ABN 已存在，会跳过迁移
- 根据 `API_BASE_URL` 自动选择映射文件（本地用 `id_mapping_local.txt`，云端用 `id_mapping.txt`）

### Brokers 迁移

**脚本**: `migrate-brokers.sh`

**功能**:

- 从旧数据库读取 Brokers（包括 NON_DIRECT_PAYMENT 和 DIRECT_PAYMENT）
- 从 ACR Register.xlsm 文件生成 CRN 映射
- 检查是否已存在（通过 email）
- 创建新的 Broker
- 保存 ID 映射关系

#### NON_DIRECT_PAYMENT Brokers

**字段映射**:

- `name` → `name`
- `name` → `email` (从 name 生成)
- `broker_group_id` → `brokerGroupId` (通过映射文件转换)
- `infinity_id` → `infinityId` (可选)
- `crn` → `crn` (从 ACR Register.xlsm 获取，或使用 `CRN_BROKER_{old_id}`)

#### DIRECT_PAYMENT Brokers (Sub-Brokers)

**字段映射**:

- `name` → `name`
- `email` → `email` (如果为空，从 name 生成)
- `broker_group_id` → `brokerGroupId` (通过映射文件转换)
- `bsb_number` → `bankAccountBsb` (直接字段)
- `account_number` → `bankAccountNumber` (直接字段)
- `abn` → `abn` (直接字段，存储在 extra_info 中)
- `address` → `address` (直接字段，存储在 extra_info 中)
- `phone` → `phone` (直接字段，存储在 extra_info 中)
- `account_name` → `accountName` (直接字段，存储在 extra_info 中)
- `crn` → `crn` (从 ACR Register.xlsm 获取，或使用 `CRN_SUB_BROKER_{old_id}`)

**重要**: `deduct` 字段不会被迁移。

---

## 数据映射关系

### Broker Group 映射

| 老系统字段       | 新系统字段            | 转换规则                                           |
| ---------------- | --------------------- | -------------------------------------------------- |
| `id`             | -                     | 不迁移，使用新 ID                                  |
| `name`           | `name`                | 直接映射                                           |
| `abn`            | `abn`                 | 清理非数字字符，转换为数字                         |
| `account_name`   | `bankAccountName`     | 直接映射，如果为空使用默认值                       |
| `bsb_number`     | `bankAccountBsb`      | 清理非数字字符，转换为整数                         |
| `account_number` | `bankAccountNumber`   | 清理非数字字符，转换为整数                         |
| `email`          | `email`               | 可选，直接字段                                     |
| `phone`          | `phoneNumber`         | 可选，直接字段                                     |
| `address`        | `address`             | 可选，直接字段                                     |
| -                | `aggregatorCompanyId` | 必须指定，默认使用环境变量 `AGGREGATOR_COMPANY_ID` |

### Broker 映射

#### 从 `broker` 表迁移（→ NON_DIRECT_PAYMENT）

| 老系统字段        | 新系统字段      | 转换规则                                                 |
| ----------------- | --------------- | -------------------------------------------------------- |
| `id`              | -               | 不迁移，使用新 ID                                        |
| `name`            | `name`          | 直接映射                                                 |
| `name`            | `email`         | 从 name 生成：`{name_clean}_{old_id}@migrated.local`     |
| `broker_group_id` | `brokerGroupId` | 映射到新系统的 Broker Group ID                           |
| `infinity_id`     | `infinityId`    | 直接映射（可选）                                         |
| -                 | `type`          | `NON_DIRECT_PAYMENT`                                     |
| -                 | `crn`           | 从 ACR Register.xlsm 获取，或生成：`CRN_BROKER_{old_id}` |

#### 从 `sub_broker` 表迁移（→ DIRECT_PAYMENT）

| 老系统字段        | 新系统字段          | 转换规则                                                     |
| ----------------- | ------------------- | ------------------------------------------------------------ |
| `id`              | -                   | 不迁移，使用新 ID                                            |
| `email`           | `email`             | 直接映射（如果为空，从 name 生成）                           |
| `name`            | `name`              | 直接映射                                                     |
| `broker_group_id` | `brokerGroupId`     | 映射到新系统的 Broker Group ID                               |
| `infinity_id`     | `infinityId`        | 直接映射（可选）                                             |
| `bsb_number`      | `bankAccountBsb`    | 清理非数字字符，转换为整数，作为**直接字段**                 |
| `account_number`  | `bankAccountNumber` | 清理非数字字符，转换为整数，作为**直接字段**                 |
| `abn`             | `abn`               | 作为**直接字段**，存储在 extra_info 中（可选）               |
| `address`         | `address`           | 作为**直接字段**，存储在 extra_info 中（可选）               |
| `phone`           | `phone`             | 作为**直接字段**，存储在 extra_info 中（可选）               |
| `account_name`    | `accountName`       | 作为**直接字段**，存储在 extra_info 中（可选）               |
| `deduct`          | -                   | **不迁移**                                                   |
| -                 | `type`              | `DIRECT_PAYMENT`                                             |
| -                 | `crn`               | 从 ACR Register.xlsm 获取，或生成：`CRN_SUB_BROKER_{old_id}` |

### Broker Type 判断逻辑

```sql
-- 老系统查询 NON_DIRECT_PAYMENT brokers
SELECT * FROM broker
WHERE deleted IS NULL
  AND (sub_broker_id IS NULL OR sub_broker_id = 0)
  AND (broker_group_id IS NOT NULL AND broker_group_id != 0);

-- 老系统查询 DIRECT_PAYMENT brokers
SELECT * FROM sub_broker
WHERE deleted IS NULL;
```

**迁移时的处理**:

1. 优先检查 `sub_broker_id`：
   - 如果 `sub_broker_id IS NOT NULL AND sub_broker_id != 0` → 跳过（应该从 `sub_broker` 表迁移）
2. 从 `broker` 表迁移 → `NON_DIRECT_PAYMENT`
3. 从 `sub_broker` 表迁移 → `DIRECT_PAYMENT`

**重要**: 即使是 `DIRECT_PAYMENT` broker，在新系统中也必须关联到一个 Broker Group。

---

## 迁移注意事项

### 0. 数据库连接配置

#### 老数据库在 Kubernetes 集群中（推荐使用 port-forward）

如果老数据库（HaiMoney）在 Kubernetes 集群中运行，需要使用 `kubectl port-forward` 来建立连接：

**步骤 1：设置环境变量**

```bash
# 启用 port-forward 模式
export USE_PORT_FORWARD="true"

# 设置 KUBECONFIG 文件路径
export KUBECONFIG_FILE="../../haimoney/haimoney-infrastructure/connection-file/haimoney-staging-cluster-kubeconfig.yaml"
# 或生产环境
export KUBECONFIG_FILE="../../haimoney/haimoney-infrastructure/connection-file/haimoney-commissions-cluster-PROD-kubeconfig.yaml"

# 设置 Kubernetes service 名称（broker 数据库）
export KUBERNETES_SERVICE="broker-db"

# 设置本地转发端口（避免与本地 PostgreSQL 冲突）
export PORT_FORWARD_PORT="5434"

# 选择环境（staging 或 production）
export ENVIRONMENT="staging"  # 或 "production"

# 数据库认证信息
export OLD_DB_USER="postgres"
export OLD_DB_NAME="broker"
export OLD_DB_PASS="postgres"  # 根据实际情况调整
```

**步骤 2：运行迁移脚本**

迁移脚本会自动：

- 启动 `kubectl port-forward svc/broker-db 5434:5432`
- 使用 `localhost:5434` 连接数据库
- 在脚本退出时自动关闭 port-forward

#### 老数据库在本地

如果老数据库在本地运行，直接设置连接信息：

```bash
export USE_PORT_FORWARD="false"
export OLD_DB_HOST="localhost"
export OLD_DB_PORT="5432"
export OLD_DB_USER="postgres"
export OLD_DB_NAME="broker"
export OLD_DB_PASS="your_password"
```

### 1. 数据唯一性约束

**Broker Group**:

- `name` 必须唯一
- `abn` 必须唯一

**Broker**:

- `email` 必须唯一
- `crn` 必须唯一

### 2. 必需字段处理

如果老系统数据缺少必需字段，需要设置默认值：

**Broker Group**:

- `abn`: 如果为空，生成 `1000000000{old_id}`
- `bankAccountName`: 如果为空，使用 `"{name} Bank Account"`
- `bankAccountBsb`: 如果为空，使用 `123456`
- `bankAccountNumber`: 如果为空，使用 `12345678`

**Broker**:

- `crn`: 如果为空，从 ACR Register.xlsm 获取，或生成 `CRN_{old_id}`
- `brokerGroupId`: 必须指定，即使是 `DIRECT_PAYMENT`

### 3. 数据清理

**ABN/BSB/Account Number**:

- 移除所有非数字字符
- 转换为数字类型

**示例**:

```bash
# ABN: "12 345 678 901" → 12345678901
# BSB: "123-456" → 123456
# Account: "12-3456-78" → 12345678
```

### 4. ID 映射

由于新系统使用新的 ID，需要维护 ID 映射关系：

**Broker Group ID 映射**:

```
old_broker_group_id -> new_company_id
```

**Broker ID 映射**:

```
old_broker_id -> new_broker_id
```

在迁移关联数据时，需要使用映射后的 ID。

### 5. 迁移顺序

1. **先迁移 Broker Groups**

   - 创建所有 Broker Groups
   - 建立 ID 映射关系
   - 创建 Aggregator-BrokerGroup 关联

2. **再迁移 Brokers**

   - 使用映射后的 `brokerGroupId`
   - 根据老系统数据判断 `type`
   - 创建 BrokerGroup-Broker 关联

3. **迁移 Fee Models**（可选）

   - 迁移 Fee Models 和 Fee Items
   - 使用映射后的 `companyId`（Broker Group ID）

4. **迁移 Commission Models**（可选）

   - 将老系统的扁平结构转换为新系统的树形结构
   - 使用映射后的 `companyId`（Broker Group ID）
   - 注意百分比转换（0-100 → 0-1）

5. **迁移 Clients**（可选）

   - 如果老系统有独立的 clients 表，迁移客户信息
   - 使用映射后的 `brokerId`
   - 创建关联的 `loan_applicants` 记录

6. **迁移 Loans**（可选）
   - 迁移贷款信息
   - 使用映射后的 `brokerId`、`brokerGroupId`、`aggregatorId`
   - 关联到对应的 Client

### 6. 错误处理

**已存在的数据**:

- 如果 Broker Group 已存在（通过 `name` 或 `abn` 匹配），跳过创建，使用现有 ID
- 如果 Broker 已存在（通过 `email` 匹配），跳过创建

**API 错误**:

- HTTP 400: 检查是否是 "already exists" 错误，如果是则继续
- HTTP 500: 检查错误信息，如果是重复数据则继续

---

## 常见问题

### 1. DIRECT_PAYMENT Broker 迁移失败（500 错误）

**问题**: 云端返回 "Internal Server Error"

**原因**: 云端后端的 `BrokerRequest` 类缺少 `abn`, `address`, `phone`, `accountName` 字段

**解决方案**: 确保云端后端代码已更新，包含这 4 个字段

**验证**: 运行测试请求，确认可以成功创建 DIRECT_PAYMENT broker

### 2. Broker Group 迁移失败（ABN 冲突）

**问题**: "A broker group with the ABN \"...\" already exists"

**原因**: 旧系统中存在重复的 ABN，或该 Broker Group 已经迁移过

**解决方案**: 这是预期行为，迁移脚本会自动跳过已存在的记录

### 3. Broker 迁移失败（Broker Group 未映射）

**问题**: "无法找到 broker_group_id {id} 的映射"

**原因**: 该 Broker 依赖的 Broker Group 迁移失败

**解决方案**: 先确保所有 Broker Groups 都成功迁移

### 4. 本地和云端使用不同的映射文件

**问题**: 本地迁移后，云端迁移时使用了本地的映射文件

**解决方案**: 脚本会自动根据 `API_BASE_URL` 选择正确的映射文件：

- 本地 (`localhost` 或 `127.0.0.1`) → `id_mapping_local.txt`
- 云端 → `id_mapping.txt`

### 5. 环境选择问题

**问题**: 迁移的数据数量不对（例如：期望 144 个 Broker Groups，但只找到 120 个）

**原因**: 可能连接到了 staging 环境而不是 production 环境

**解决方案**: 确保设置了 `ENVIRONMENT=production` 环境变量

---

## API 端点参考

### Broker Group

- **创建**: `POST /api/company/broker-group`
- **查询**: `GET /api/company?type=BROKER_GROUP`
- **查询（按 ABN）**: `GET /api/company?abn={abn}`
- **删除**: `DELETE /api/company/{id}`

### Broker

- **创建**: `POST /api/broker`
- **查询**: `GET /api/broker`
- **查询（按邮箱）**: `GET /api/broker?email={email}`
- **查询（按 Broker Group）**: `GET /api/broker?brokerGroupId={id}`
- **删除**: `DELETE /api/broker/{id}`

### 认证

- **登录**: `POST /api/auth/login`
  ```json
  {
    "identityType": "EMAIL",
    "identity": "email@example.com",
    "password": "password"
  }
  ```

---

## 环境变量

### 必需变量

- `OLD_DB_PASS`: 旧数据库密码（必需）

### 可选变量

- `API_BASE_URL`: 新系统 API 地址（默认: `http://13.54.207.94/api`）
- `ENVIRONMENT`: 环境选择，`staging` 或 `production`（默认: `staging`）
- `USE_PORT_FORWARD`: 是否使用 Kubernetes port-forward（默认: `false`）
- `KUBECONFIG_FILE`: Kubernetes 配置文件路径
- `KUBERNETES_SERVICE`: Kubernetes service 名称（默认: `broker-db`）
- `PORT_FORWARD_PORT`: Port-forward 本地端口（默认: `5434`）
- `FORCE_NEW_MAPPING`: 强制重新生成映射文件（默认: `false`）
- `FORCE_DELETE`: 清理脚本跳过确认（默认: `false`）
- `LOGIN_EMAIL`: API 登录邮箱（默认: `haimoneySupport@harbourx.com.au`）
- `LOGIN_PASSWORD`: API 登录密码（默认: `password`）
- `AGGREGATOR_COMPANY_ID`: Aggregator 公司 ID（默认: `1`）

---

## 相关文件

### 脚本文件

- `migrate-all.sh` - 完整迁移脚本（按顺序执行）
- `migrate-broker-groups.sh` - Broker Groups 迁移脚本
- `migrate-brokers.sh` - Brokers 迁移脚本
- `clean-cloud-data.sh` - 清理云端数据脚本

### 数据文件

- `id_mapping.txt` - 云端 ID 映射文件
- `id_mapping_local.txt` - 本地 ID 映射文件
- `acr_crn_mapping.csv` - CRN 映射文件（从 ACR Register.xlsm 生成）

### 日志文件

迁移脚本会生成日志文件：

- `migrate-all-{timestamp}.log` - 完整迁移日志
- `migrate-broker-groups-{timestamp}.log` - Broker Groups 迁移日志
- `migrate-brokers-{timestamp}.log` - Brokers 迁移日志

日志包含：

- 迁移进度
- 成功/失败记录
- 错误信息

---

## 迁移失败报告

### 本地迁移失败（预期）

**Broker Groups**: 3 个未迁移（ABN 冲突）

- BW AUSTRALIA PTY LTD (Old) (ID: 10)
- AUSTRALIAN HOUSING FUND PTY LTD(Mentee) (ID: 215)
- EFS ADVISORS PTY LTD (ID: 239)

**NON_DIRECT_PAYMENT Brokers**: 4 个未迁移（Broker Group 未映射）

- 依赖的 Broker Groups 因为 ABN 冲突而迁移失败

**DIRECT_PAYMENT Brokers**: 2 个未迁移（Broker Group 已删除）

- Reema Monga (Broker Group ID 150 已删除)
- Manpreet Kaur (Broker Group ID 150 已删除)

---

## 总结

### 核心实体

1. **Broker Group**: 老系统的 `broker_group` 表 → 新系统的 `companies` (type=2)
2. **Broker**:
   - 老系统的 `broker` 表 → 新系统的 `NON_DIRECT_PAYMENT` brokers
   - 老系统的 `sub_broker` 表 → 新系统的 `DIRECT_PAYMENT` brokers
   - **重要**: `sub_broker` 的 `bsb_number` 和 `account_number` 直接映射到 `bankAccountBsb` 和 `bankAccountNumber` 字段
   - **重要**: `sub_broker` 的 `abn`, `address`, `phone`, `account_name` 作为直接字段（存储在 extra_info 中）
3. **类型判断**: 从 `broker` 表迁移 → `NON_DIRECT_PAYMENT`，从 `sub_broker` 表迁移 → `DIRECT_PAYMENT`
4. **关联关系**: 通过 `aggregator_broker_groups` 和 `broker_group_brokers` 表维护

### 其他实体

5. **Fee Model**: 老系统的 `fee_models` + `fee_items` → 新系统的 `fee_models` + `fee_model_items`
6. **Commission Model**: 老系统的 `commission_models` + `commission_items` → 新系统的 `commission_templates` + `commission_template_items`（树形结构）
7. **Client**: 老系统可能没有独立表（信息在 loans 中） → 新系统的 `clients` + `loan_applicants`
8. **Loan**: 老系统的 `loans` → 新系统的 `loans`（需要 `aggregator_id`）

### 通用规则

9. **必需字段**: 确保所有必需字段都有值，缺失时使用默认值
10. **唯一性**: 注意 `name`、`abn`（Broker Group）、`email`、`crn`（Broker）的唯一性约束
11. **ID 映射**: 维护所有实体的 ID 映射关系，用于关联数据迁移
12. **数据转换**: 注意百分比转换（Commission: 0-100 → 0-1）、数据清理（ABN/BSB/Account Number）
