# 数据迁移结构说明文档

本文档详细说明老系统（HaiMoney）和新系统（HarbourX）中所有主要实体的数据结构对应关系，包括 Broker、Broker Group、Fee Model、Commission Model、Client 和 Loan。

## 目录

1. [Broker Group 数据结构](#broker-group-数据结构)
2. [Broker 数据结构](#broker-数据结构)
3. [Fee Model 数据结构](#fee-model-数据结构)
4. [Commission Model 数据结构](#commission-model-数据结构)
5. [Client 数据结构](#client-数据结构)
6. [Loan 数据结构](#loan-数据结构)
7. [数据映射关系](#数据映射关系)
8. [迁移注意事项](#迁移注意事项)

---

## Broker Group 数据结构

### 老系统（HaiMoney）表结构

**表名**: `companies` (type = 2 表示 Broker Group)

| 字段名             | 类型      | 说明                        | 是否必需 |
| ------------------ | --------- | --------------------------- | -------- |
| `id`               | BIGINT    | 主键 ID                     | ✅       |
| `type`             | SMALLINT  | 公司类型，2 = Broker Group  | ✅       |
| `name`             | VARCHAR   | 公司名称                    | ✅       |
| `abn`              | BIGINT    | ABN 号码                    | ✅       |
| `account_name`     | VARCHAR   | 银行账户名称                | ✅       |
| `bsb_number`       | VARCHAR   | BSB 号码                    | ✅       |
| `account_number`   | VARCHAR   | 银行账户号码                | ✅       |
| `unique_reference` | VARCHAR   | 唯一引用号（CRN）           | ✅       |
| `email`            | VARCHAR   | 邮箱（可选）                | ❌       |
| `phone`            | VARCHAR   | 电话（可选）                | ❌       |
| `address`          | VARCHAR   | 地址（可选）                | ❌       |
| `infinity_id`      | BIGINT    | Infinity ID（可选）         | ❌       |
| `deleted`          | TIMESTAMP | 删除时间（NULL 表示未删除） | -        |

**查询示例**:

```sql
SELECT id, name, abn, account_name, bsb_number, account_number,
       email, phone, address, infinity_id
FROM companies
WHERE type = 2 AND deleted IS NULL;
```

### 新系统（HarbourX）表结构

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

### API 请求结构

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
  "email": "email@example.com", // 可选
  "phoneNumber": "+61 2 1234 5678", // 可选
  "address": "123 Street, City", // 可选
  "website": "https://example.com", // 可选
  "directorInformation": "Director Info", // 可选
  "acl": "ACL string" // 可选
}
```

---

## Broker 数据结构

### 老系统（HaiMoney）表结构

**表名**: `broker`

| 字段名             | 类型      | 说明                                  | 是否必需 | 迁移说明          |
| ------------------ | --------- | ------------------------------------- | -------- | ----------------- |
| `id`               | INT       | 主键 ID                               | ✅       | 不迁移，使用新 ID |
| `name`             | STRING    | 名称                                  | ✅       | 用于生成 email    |
| `broker_group_id`  | INT       | Broker Group ID                       | ✅       | 映射到新系统      |
| `sub_broker_id`    | INT       | Sub Broker ID（指向 `sub_broker` 表） | -        | 用于判断类型      |
| `infinity_id`      | INT       | Infinity ID（可选）                   | ❌       | 直接迁移          |
| `unique_reference` | STRING    | 唯一引用号                            | ✅       | **不迁移**        |
| `is_sub_broker`    | BOOL      | 是否为 sub_broker                     | -        | 用于判断类型      |
| `created`          | TIMESTAMP | 创建时间                              | ✅       | -                 |
| `updated`          | TIMESTAMP | 更新时间                              | ✅       | -                 |
| `deleted`          | TIMESTAMP | 删除时间（NULL 表示未删除）           | -        | 只迁移未删除的    |

**表名**: `sub_broker`

| 字段名              | 类型      | 说明                        | 是否必需 | 迁移说明                              |
| ------------------- | --------- | --------------------------- | -------- | ------------------------------------- |
| `id`                | INT       | 主键 ID                     | ✅       | 不迁移，使用新 ID                     |
| `name`              | STRING    | 名称                        | ✅       | 用于生成 email                        |
| `email`             | STRING    | 邮箱（唯一）                | ❌       | 直接迁移                              |
| `broker_group_id`   | INT       | Broker Group ID             | ✅       | 映射到新系统                          |
| `abn`               | STRING    | ABN 号码                    | ❌       | 放入 extra_info                       |
| `address`           | STRING    | 地址                        | ❌       | 放入 extra_info                       |
| `phone`             | STRING    | 电话                        | ❌       | 放入 extra_info                       |
| `infinity_id`       | INT       | Infinity ID（可选）         | ❌       | 直接迁移                              |
| `commissions_model` | INT       | Commission Model ID         | ✅       | 待实现                                |
| `fee_model`         | INT       | Fee Model ID                | ✅       | 待实现                                |
| `deduct`            | BOOL      | 是否扣除                    | ✅       | 放入 extra_info                       |
| `account_name`      | STRING    | 账户名称                    | ❌       | 放入 extra_info                       |
| `bsb_number`        | STRING    | BSB 号码                    | ❌       | **直接映射到 bankAccountBsb 字段**    |
| `account_number`    | STRING    | 账户号码                    | ❌       | **直接映射到 bankAccountNumber 字段** |
| `unique_reference`  | STRING    | 唯一引用号                  | ✅       | **不迁移**                            |
| `created`           | TIMESTAMP | 创建时间                    | ✅       | -                                     |
| `updated`           | TIMESTAMP | 更新时间                    | ✅       | -                                     |
| `deleted`           | TIMESTAMP | 删除时间（NULL 表示未删除） | -        | 只迁移未删除的                        |

**重要逻辑**:

- **`broker` 表** → 新系统 **`NON_DIRECT_PAYMENT` broker**
  - 使用 `broker.broker_group_id` 映射到新系统的 broker_group_id
  - 从 `broker.name` 生成 email（格式：`{name_clean}_{old_id}@migrated.local`）
  - `unique_reference` **不迁移**
  - `bsb_number` 和 `account_number` **不迁移**（broker 表没有这些字段）
- **`sub_broker` 表** → 新系统 **`DIRECT_PAYMENT` broker**
  - 使用 `sub_broker.broker_group_id` 映射到新系统的 broker_group_id
  - 使用 `sub_broker.email`（如果为空，从 `sub_broker.name` 生成）
  - `bsb_number` 和 `account_number` **直接映射到 `bankAccountBsb` 和 `bankAccountNumber` 字段**（不放入 extra_info）
  - `abn`, `address`, `phone`, `deduct`, `account_name` 放入 `extra_info` JSON 字段
  - `unique_reference` **不迁移**
- **特殊情况**：
  - 如果 `broker.sub_broker_id != 0`，表示该 broker 关联到一个 sub_broker
  - 此时应该迁移 `sub_broker` 表中的记录，而不是 `broker` 表中的记录
  - 如果 `broker.broker_group_id = 0` 且 `sub_broker_id = 0`，使用 Direct Payment Brokers Group

**查询示例**:

```sql
-- 所有未删除的 brokers
SELECT id, email, broker_group_id, sub_broker_id,
       infinity_id, acl, unique_reference
FROM brokers
WHERE deleted IS NULL;

-- Sub brokers (DIRECT_PAYMENT)
SELECT * FROM brokers
WHERE deleted IS NULL
  AND (broker_group_id = 0 OR broker_group_id IS NULL);

-- 或者
SELECT * FROM brokers
WHERE deleted IS NULL
  AND sub_broker_id IS NOT NULL
  AND sub_broker_id != 0;
```

### 新系统（HarbourX）表结构

**表名**: `brokers`

| 字段名                | 类型      | 说明                                                | 是否必需 | 迁移来源                                                                         |
| --------------------- | --------- | --------------------------------------------------- | -------- | -------------------------------------------------------------------------------- |
| `id`                  | BIGINT    | 主键 ID                                             | ✅       | 新生成                                                                           |
| `user_id`             | BIGINT    | 关联用户 ID（可选）                                 | ❌       | -                                                                                |
| `name`                | VARCHAR   | Broker 名称                                         | ✅       | `broker.name` 或 `sub_broker.name`                                               |
| `email`               | VARCHAR   | 邮箱（唯一）                                        | ✅       | `sub_broker.email` 或从 `name` 生成                                              |
| `type`                | SMALLINT  | Broker 类型：1=DIRECT_PAYMENT, 2=NON_DIRECT_PAYMENT | ✅       | `broker`→NON_DIRECT_PAYMENT, `sub_broker`→DIRECT_PAYMENT                         |
| `infinity_id`         | BIGINT    | Infinity ID（可选）                                 | ❌       | `broker.infinity_id` 或 `sub_broker.infinity_id`                                 |
| `acl`                 | VARCHAR   | ACL 权限（可选）                                    | ❌       | -                                                                                |
| `crn`                 | VARCHAR   | CRN 号码（唯一）                                    | ✅       | 生成（格式：`CRN_BROKER_{old_id}` 或 `CRN_SUB_BROKER_{old_id}`）                 |
| `bank_account_bsb`    | INTEGER   | BSB 号码（可选，仅 DIRECT_PAYMENT）                 | ❌       | `sub_broker.bsb_number`（直接字段，不放入 extra_info）                           |
| `bank_account_number` | INTEGER   | 银行账户号码（可选，仅 DIRECT_PAYMENT）             | ❌       | `sub_broker.account_number`（直接字段，不放入 extra_info）                       |
| `extra_info`          | JSONB     | 额外信息（JSON）                                    | ❌       | 包含 `abn`, `address`, `phone`, `deduct`, `accountName` 等（不包含 bsb/account） |
| `created_at`          | TIMESTAMP | 创建时间                                            | ✅       | 新生成                                                                           |
| `updated_at`          | TIMESTAMP | 更新时间                                            | ✅       | 新生成                                                                           |

**`extra_info` JSON 结构示例**（对于 sub_broker）:

```json
{
  "abn": "12345678901",
  "address": "123 Street, City",
  "phone": "+61 2 1234 5678",
  "deduct": true,
  "accountName": "Account Name"
}
```

**注意**: `bsb_number` 和 `account_number` 现在作为直接字段 `bank_account_bsb` 和 `bank_account_number`，不再存储在 `extra_info` 中。

**关联表**: `broker_group_brokers`

- `broker_group_id`: Broker Group 公司 ID
- `broker_id`: Broker ID
- `created_at`: 关联创建时间
- `deleted_at`: 软删除时间（NULL 表示未删除）

**重要**: 即使是 `DIRECT_PAYMENT` broker，也必须关联到一个 Broker Group（不能为 NULL）

### API 请求结构

**端点**: `POST /api/broker`

**请求体** (`BrokerRequest`):

```json
{
  "name": "Broker Name",
  "email": "broker@example.com",
  "type": "DIRECT_PAYMENT", // 或 "NON_DIRECT_PAYMENT"
  "crn": "CRN123456",
  "brokerGroupId": 1, // 必需，即使是 DIRECT_PAYMENT
  "infinityId": 12345, // 可选
  "bankAccountBsb": 123456, // 可选，仅 DIRECT_PAYMENT（来自 sub_broker.bsb_number）
  "bankAccountNumber": 12345678, // 可选，仅 DIRECT_PAYMENT（来自 sub_broker.account_number）
  "extraInfo": {
    // 可选，仅 DIRECT_PAYMENT
    "abn": "12345678901",
    "address": "123 Street, City",
    "phone": "+61 2 1234 5678",
    "deduct": true,
    "accountName": "Account Name"
  },
  "acl": "ACL string" // 可选
}
```

**BrokerType 枚举**:

- `DIRECT_PAYMENT` (typeId = 1)
- `NON_DIRECT_PAYMENT` (typeId = 2)

---

## Fee Model 数据结构

### 老系统（HaiMoney）表结构

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

**查询示例**:

```sql
-- 查询所有未删除的 Fee Models
SELECT fm.id, fm.company_id, fm.user_id, fm.name, fm.description
FROM fee_models fm
WHERE fm.deleted IS NULL;

-- 查询 Fee Model 的所有 Items
SELECT fi.id, fi.model_id, fi.description, fi.type, fi.amount
FROM fee_items fi
WHERE fi.model_id = ? AND fi.deleted IS NULL;
```

### 新系统（HarbourX）表结构

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

### API 请求结构

**端点**: `POST /api/fee/model`

**请求体**:

```json
{
  "companyId": 1,
  "name": "Fee Model Name",
  "description": "Description",
  "items": [
    {
      "description": "Item 1",
      "type": "PER_LOAN",
      "amount": 100.0
    },
    {
      "description": "Item 2",
      "type": "PER_MONTH",
      "amount": 50.0
    }
  ]
}
```

**FeeItemType 枚举**:

- `PER_LOAN` (typeId = 1)
- `PER_MONTH` (typeId = 2)
- `WITHHOLDING` (typeId = 3)

---

## Commission Model 数据结构

### 老系统（HaiMoney）表结构

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

**查询示例**:

```sql
-- 查询所有未删除的 Commission Models
SELECT cm.id, cm.company_id, cm.user_id, cm.name, cm.description
FROM commission_models cm
WHERE cm.deleted IS NULL;

-- 查询 Commission Model 的所有 Items
SELECT ci.id, ci.model_id, ci.description,
       ci.from_node_binding_type, ci.from_node_binding_id,
       ci.to_node_binding_type, ci.to_node_binding_id,
       ci.allocation_type, ci.upfront_percentage, ci.trail_percentage
FROM commission_items ci
WHERE ci.model_id = ? AND ci.deleted IS NULL;
```

### 新系统（HarbourX）表结构

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

### API 请求结构

**端点**: `POST /api/commission/template`

**请求体** (`CommissionTemplate`):

```json
{
  "companyId": 1,
  "name": "Commission Template Name",
  "description": "Description",
  "root": {
    "description": "Total",
    "nodeIdentity": {
      "nodeBindingType": "UNBOUND",
      "nodeType": "TOTAL"
    },
    "children": [
      {
        "description": "Broker",
        "nodeIdentity": {
          "nodeBindingType": "SPECIFIED_COMPANY",
          "nodeType": "BROKER",
          "companyId": 123
        },
        "allocationType": "PERCENTAGE",
        "allocationValueUpfront": 0.8,
        "allocationValueTrail": 0.8,
        "children": []
      }
    ]
  }
}
```

**重要转换**:

- 老系统的 `upfront_percentage` 和 `trail_percentage` 是 0-100 的整数
- 新系统的 `allocationValueUpfront` 和 `allocationValueTrail` 是 0-1 的小数
- 需要将百分比除以 100 进行转换

---

## Client 数据结构

### 老系统（HaiMoney）表结构

**表名**: `clients` (如果存在)

| 字段名       | 类型      | 说明                        | 是否必需 |
| ------------ | --------- | --------------------------- | -------- |
| `id`         | BIGINT    | 主键 ID                     | ✅       |
| `name`       | VARCHAR   | 客户名称                    | ✅       |
| `broker_id`  | BIGINT    | Broker ID                   | ✅       |
| `email`      | VARCHAR   | 邮箱（可选）                | ❌       |
| `phone`      | VARCHAR   | 电话（可选）                | ❌       |
| `created_at` | TIMESTAMP | 创建时间                    | ✅       |
| `updated_at` | TIMESTAMP | 更新时间                    | ✅       |
| `deleted`    | TIMESTAMP | 删除时间（NULL 表示未删除） | -        |

**注意**: 老系统可能没有独立的 `clients` 表，客户信息可能存储在 `loans` 表的 `client_name` 字段中。

### 新系统（HarbourX）表结构

**表名**: `clients`

| 字段名        | 类型      | 说明      | 是否必需 |
| ------------- | --------- | --------- | -------- |
| `id`          | BIGINT    | 主键 ID   | ✅       |
| `client_name` | VARCHAR   | 客户名称  | ✅       |
| `broker_id`   | BIGINT    | Broker ID | ✅       |
| `created_at`  | TIMESTAMP | 创建时间  | ✅       |
| `updated_at`  | TIMESTAMP | 更新时间  | ✅       |

**关联表**: `loan_applicants` (客户详细信息)

| 字段名           | 类型             | 说明                                    | 是否必需 |
| ---------------- | ---------------- | --------------------------------------- | -------- |
| `id`             | BIGINT           | 主键 ID                                 | ✅       |
| `client_id`      | BIGINT           | Client ID                               | ✅       |
| `entity_type`    | SMALLINT         | 实体类型：1=Individual, 2=Company       | ❌       |
| `applicant_type` | SMALLINT         | 申请人类型：1=Applicant, 2=Co-Applicant | ❌       |
| `title`          | VARCHAR          | 称谓（Mr., Mrs., Ms. 等）               | ❌       |
| `first_name`     | VARCHAR          | 名                                      | ✅       |
| `middle_name`    | VARCHAR          | 中间名                                  | ❌       |
| `surname`        | VARCHAR          | 姓                                      | ✅       |
| `email`          | VARCHAR          | 邮箱                                    | ✅       |
| `mobile`         | VARCHAR          | 手机                                    | ✅       |
| `date_of_birth`  | DATE             | 出生日期                                | ❌       |
| `address`        | VARCHAR          | 地址                                    | ❌       |
| `city`           | VARCHAR          | 城市                                    | ❌       |
| `state`          | VARCHAR          | 州                                      | ❌       |
| `postcode`       | VARCHAR          | 邮编                                    | ❌       |
| `occupation`     | VARCHAR          | 职业                                    | ❌       |
| `income`         | DOUBLE PRECISION | 收入                                    | ❌       |
| `created_at`     | TIMESTAMP        | 创建时间                                | ✅       |
| `updated_at`     | TIMESTAMP        | 更新时间                                | ✅       |

### API 请求结构

**端点**: `POST /api/client`

**请求体** (`ClientRequest`):

```json
{
  "clientName": "Client Name",
  "brokerId": 1,
  "loanApplicant": {
    "firstName": "John",
    "surname": "Doe",
    "email": "john.doe@example.com",
    "mobile": "+61 4 1234 5678",
    "dateOfBirth": "1990-01-01",
    "address": "123 Street",
    "city": "Sydney",
    "state": "NSW",
    "postcode": "2000"
  }
}
```

---

## Loan 数据结构

### 老系统（HaiMoney）表结构

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

**查询示例**:

```sql
-- 查询所有未删除的 Loans
SELECT id, broker_id, broker_group_id, client_name,
       lender_name, lender_ref, settled_date, settled_amount, status
FROM loans
WHERE deleted IS NULL;
```

### 新系统（HarbourX）表结构

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

**关联表**: `clients` 和 `loan_applicants`

- 新系统中，Loan 通过 `client_name` 关联到 Client
- Client 的详细信息存储在 `loan_applicants` 表中

### API 请求结构

**端点**: `POST /api/loan`

**请求体**:

```json
{
  "brokerId": 1,
  "brokerGroupId": 1,
  "aggregatorId": 1,
  "clientName": "Client Name",
  "lenderName": "Lender Name",
  "lenderRef": "REF123456",
  "settledDate": "2024-01-01",
  "settledAmount": 500000.0,
  "status": 1
}
```

---

## 数据映射关系

### Broker Group 映射

| 老系统字段         | 新系统字段                 | 转换规则                                           |
| ------------------ | -------------------------- | -------------------------------------------------- |
| `id`               | -                          | 不迁移，使用新 ID                                  |
| `name`             | `name`                     | 直接映射                                           |
| `abn`              | `abn`                      | 清理非数字字符，转换为数字                         |
| `account_name`     | `bankAccountName`          | 直接映射，如果为空使用默认值                       |
| `bsb_number`       | `bankAccountBsb`           | 清理非数字字符，转换为整数                         |
| `account_number`   | `bankAccountNumber`        | 清理非数字字符，转换为整数                         |
| `unique_reference` | -                          | **不迁移**（companies 表不再有 crn 字段）          |
| `email`            | `email` (extra_info)       | 可选，放入 extra_info                              |
| `phone`            | `phoneNumber` (extra_info) | 可选，放入 extra_info                              |
| `address`          | `address` (extra_info)     | 可选，放入 extra_info                              |
| -                  | `aggregatorCompanyId`      | 必须指定，默认使用环境变量 `AGGREGATOR_COMPANY_ID` |

### Broker 映射

#### 从 `broker` 表迁移（→ NON_DIRECT_PAYMENT）

| 老系统字段         | 新系统字段      | 转换规则                                             |
| ------------------ | --------------- | ---------------------------------------------------- |
| `id`               | -               | 不迁移，使用新 ID                                    |
| `name`             | `email`         | 从 name 生成：`{name_clean}_{old_id}@migrated.local` |
| `broker_group_id`  | `brokerGroupId` | 映射到新系统的 Broker Group ID                       |
| `infinity_id`      | `infinityId`    | 直接映射（可选）                                     |
| `unique_reference` | -               | **不迁移**                                           |
| `bsb_number`       | -               | **不迁移**（broker 表没有此字段）                    |
| `account_number`   | -               | **不迁移**（broker 表没有此字段）                    |
| -                  | `type`          | `NON_DIRECT_PAYMENT`                                 |
| -                  | `crn`           | 生成：`CRN_BROKER_{old_id}`                          |

#### 从 `sub_broker` 表迁移（→ DIRECT_PAYMENT）

| 老系统字段         | 新系统字段               | 转换规则                                                          |
| ------------------ | ------------------------ | ----------------------------------------------------------------- |
| `id`               | -                        | 不迁移，使用新 ID                                                 |
| `email`            | `email`                  | 直接映射（如果为空，从 name 生成）                                |
| `name`             | -                        | 如果 email 为空，用于生成 email                                   |
| `broker_group_id`  | `brokerGroupId`          | 映射到新系统的 Broker Group ID                                    |
| `infinity_id`      | `infinityId`             | 直接映射（可选）                                                  |
| `bsb_number`       | `bankAccountBsb`         | 清理非数字字符，转换为整数，作为**直接字段**（不放入 extra_info） |
| `account_number`   | `bankAccountNumber`      | 清理非数字字符，转换为整数，作为**直接字段**（不放入 extra_info） |
| `abn`              | `extra_info.abn`         | 放入 extra_info JSON（可选）                                      |
| `address`          | `extra_info.address`     | 放入 extra_info JSON（可选）                                      |
| `phone`            | `extra_info.phone`       | 放入 extra_info JSON（可选）                                      |
| `deduct`           | `extra_info.deduct`      | 放入 extra_info JSON（可选）                                      |
| `account_name`     | `extra_info.accountName` | 放入 extra_info JSON（可选）                                      |
| `unique_reference` | -                        | **不迁移**                                                        |
| -                  | `type`                   | `DIRECT_PAYMENT`                                                  |
| -                  | `crn`                    | 生成：`CRN_SUB_BROKER_{old_id}`                                   |

### Broker Type 判断逻辑

```sql
-- 老系统查询 DIRECT_PAYMENT brokers
SELECT * FROM brokers
WHERE deleted IS NULL
  AND (
    (broker_group_id = 0 OR broker_group_id IS NULL)
    OR (sub_broker_id IS NOT NULL AND sub_broker_id != 0)
  );

-- 老系统查询 NON_DIRECT_PAYMENT brokers
SELECT * FROM brokers
WHERE deleted IS NULL
  AND broker_group_id > 0
  AND broker_group_id IS NOT NULL
  AND (sub_broker_id IS NULL OR sub_broker_id = 0);
```

**迁移时的处理**:

1. 优先检查 `sub_broker_id`：
   - 如果 `sub_broker_id IS NOT NULL AND sub_broker_id != 0` → `DIRECT_PAYMENT`
2. 其次检查 `broker_group_id`：
   - 如果 `broker_group_id = 0 OR broker_group_id IS NULL` → `DIRECT_PAYMENT`
3. 其他情况 → `NON_DIRECT_PAYMENT`

**重要**: 即使是 `DIRECT_PAYMENT` broker，在新系统中也必须关联到一个 Broker Group。如果老系统的 `broker_group_id = 0`，需要：

1. 创建一个特殊的 "Direct Payment Brokers" Broker Group（如果不存在）
2. 将所有 `DIRECT_PAYMENT` brokers 关联到这个组

---

## 迁移注意事项

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

- `crn`: 如果为空，生成 `CRN_{old_id}`
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

**Fee Model ID 映射**:

```
old_fee_model_id -> new_fee_model_id
```

**Commission Model ID 映射**:

```
old_commission_model_id -> new_commission_template_id
```

**Client ID 映射**:

```
old_client_id -> new_client_id
```

**Loan ID 映射**:

```
old_loan_id -> new_loan_id
```

在迁移关联数据时，需要使用映射后的 ID。

### 5. 迁移顺序

1. **先迁移 Broker Groups**

   - 创建所有 Broker Groups
   - 建立 ID 映射关系
   - 创建 Aggregator-BrokerGroup 关联

2. **处理 DIRECT_PAYMENT Brokers**

   - 检查是否存在 "Direct Payment Brokers" Broker Group
   - 如果不存在，创建它
   - 记录其 ID 用于后续映射

3. **再迁移 Brokers**

   - 使用映射后的 `brokerGroupId`
   - 根据老系统数据判断 `type`
   - 创建 BrokerGroup-Broker 关联

4. **迁移 Fee Models**（可选）

   - 迁移 Fee Models 和 Fee Items
   - 使用映射后的 `companyId`（Broker Group ID）

5. **迁移 Commission Models**（可选）

   - 将老系统的扁平结构转换为新系统的树形结构
   - 使用映射后的 `companyId`（Broker Group ID）
   - 注意百分比转换（0-100 → 0-1）

6. **迁移 Clients**（可选）

   - 如果老系统有独立的 clients 表，迁移客户信息
   - 使用映射后的 `brokerId`
   - 创建关联的 `loan_applicants` 记录

7. **迁移 Loans**（可选）
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

### 7. 特殊 Broker Group

对于老系统中 `broker_group_id = 0` 的 brokers，需要：

1. 创建一个特殊的 Broker Group：

   ```json
   {
     "name": "Direct Payment Brokers",
     "abn": 1000000000000,
     "bankAccountName": "Direct Payment Brokers Bank Account",
     "bankAccountBsb": 123456,
     "bankAccountNumber": 12345678,
     "aggregatorCompanyId": 1
   }
   ```

2. 将所有 `DIRECT_PAYMENT` brokers 关联到这个组

---

## 迁移脚本示例

### Broker Group 迁移

```bash
# 1. 从老系统导出
psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $OLD_DB_NAME \
  -c "SELECT id, name, abn, account_name, bsb_number, account_number,
      unique_reference, email, phone, address
      FROM companies
      WHERE type = 2 AND deleted IS NULL" \
  -t -A -F"," > broker_groups.csv

# 2. 转换为新系统格式并导入
while IFS=',' read -r old_id name abn account_name bsb account_number email phone address; do
  # 清理数据
  abn_clean=$(echo "$abn" | tr -d -c '0-9')
  bsb_clean=$(echo "$bsb" | tr -d -c '0-9')
  account_clean=$(echo "$account_number" | tr -d -c '0-9')

  # 构建 JSON
  json=$(jq -n \
    --arg name "$name" \
    --argjson abn "$abn_clean" \
    --arg bank_account_name "$account_name" \
    --argjson bsb "$bsb_clean" \
    --argjson account "$account_clean" \
    --argjson aggregator_id "$AGGREGATOR_COMPANY_ID" \
    '{
      name: $name,
      abn: $abn,
      bankAccountName: $bank_account_name,
      bankAccountBsb: $bsb,
      bankAccountNumber: $account,
      aggregatorCompanyId: $aggregator_id
    }')

  # 调用 API
  curl -X POST "$API_BASE_URL/company/broker-group" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$json"

  # 记录 ID 映射
  echo "$old_id:$new_id" >> id_mapping.txt
done < broker_groups.csv
```

### Broker 迁移

#### NON_DIRECT_PAYMENT Broker（来自 `broker` 表）

```bash
# 1. 从老系统导出 broker 表数据
psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $OLD_DB_NAME \
  -c "SELECT id, name, broker_group_id, infinity_id
      FROM broker
      WHERE deleted IS NULL
        AND (sub_broker_id IS NULL OR sub_broker_id = 0)
        AND (broker_group_id IS NOT NULL AND broker_group_id != 0)" \
  -t -A -F"," > brokers.csv

# 2. 转换为新系统格式并导入
while IFS=',' read -r old_id name broker_group_id infinity_id; do
  # 从 name 生成 email
  name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
  email="${name_clean}_${old_id}@migrated.local"
  crn="CRN_BROKER_${old_id}"

  # 映射 broker_group_id
  new_broker_group_id=$(grep "^${broker_group_id}:" id_mapping.txt | cut -d: -f2)

  # 构建 JSON
  json=$(jq -n \
    --arg email "$email" \
    --arg name "$name" \
    --arg type "NON_DIRECT_PAYMENT" \
    --arg crn "$crn" \
    --argjson broker_group_id "$new_broker_group_id" \
    --argjson infinity_id "${infinity_id:-null}" \
    '{
      email: $email,
      name: $name,
      type: $type,
      crn: $crn,
      brokerGroupId: $broker_group_id
    } + (if $infinity_id != "null" and $infinity_id != "0" then {infinityId: $infinity_id} else {} end)')

  # 调用 API
  curl -X POST "$API_BASE_URL/broker" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$json"
done < brokers.csv
```

#### DIRECT_PAYMENT Broker（来自 `sub_broker` 表）

```bash
# 1. 从老系统导出 sub_broker 表数据
psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $OLD_DB_NAME \
  -c "SELECT id, email, name, broker_group_id, infinity_id,
      bsb_number, account_number, abn, address, phone, deduct, account_name
      FROM sub_broker
      WHERE deleted IS NULL" \
  -t -A -F"," > sub_brokers.csv

# 2. 转换为新系统格式并导入
while IFS=',' read -r old_id email name broker_group_id infinity_id \
    bsb_number account_number abn address phone deduct account_name; do

  # 处理 email：如果为空，从 name 生成
  if [ -z "$email" ]; then
    name_clean=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 40)
    email="${name_clean}_${old_id}@migrated.local"
  fi

  crn="CRN_SUB_BROKER_${old_id}"

  # 清理 BSB 和 account number
  bsb_clean=$(echo "$bsb_number" | tr -d -c '0-9')
  account_clean=$(echo "$account_number" | tr -d -c '0-9')

  # 映射 broker_group_id
  new_broker_group_id=$(grep "^${broker_group_id}:" id_mapping.txt | cut -d: -f2)

  # 构建 extra_info JSON（不包含 bsb_number 和 account_number）
  extra_info=$(jq -n \
    --arg abn "$abn" \
    --arg address "$address" \
    --arg phone "$phone" \
    --arg deduct "$deduct" \
    --arg account_name "$account_name" \
    '{} +
    (if $abn != "" then {abn: $abn} else {} end) +
    (if $address != "" then {address: $address} else {} end) +
    (if $phone != "" then {phone: $phone} else {} end) +
    (if $deduct != "" then {deduct: ($deduct == "true" or $deduct == "t")} else {} end) +
    (if $account_name != "" then {accountName: $account_name} else {} end)')

  # 构建 JSON（bsb_number 和 account_number 作为直接字段）
  json=$(jq -n \
    --arg email "$email" \
    --arg name "$name" \
    --arg type "DIRECT_PAYMENT" \
    --arg crn "$crn" \
    --argjson broker_group_id "$new_broker_group_id" \
    --argjson infinity_id "${infinity_id:-null}" \
    --arg bsb_str "$bsb_clean" \
    --arg account_str "$account_clean" \
    --argjson extra_info "$extra_info" \
    '{
      email: $email,
      name: $name,
      type: $type,
      crn: $crn,
      brokerGroupId: $broker_group_id
    } + (if $infinity_id != "null" and $infinity_id != "0" then {infinityId: $infinity_id} else {} end) +
      (if $bsb_str != "" then {bankAccountBsb: ($bsb_str | tonumber)} else {} end) +
      (if $account_str != "" then {bankAccountNumber: ($account_str | tonumber)} else {} end) +
      (if ($extra_info | length) > 0 then {extraInfo: $extra_info} else {} end)')

  # 调用 API
  curl -X POST "$API_BASE_URL/broker" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$json"
done < sub_brokers.csv
```

---

## API 端点参考

### Broker Group

- **创建**: `POST /api/company/broker-group`
- **查询**: `GET /api/company?type=BROKER_GROUP`
- **查询（按 ABN）**: `GET /api/company?abn={abn}`

### Broker

- **创建**: `POST /api/broker`
- **查询**: `GET /api/broker`
- **查询（按邮箱）**: `GET /api/broker?email={email}`

---

## 总结

### 核心实体

1. **Broker Group**: 老系统的 `companies` (type=2) → 新系统的 `companies` (type=2)
2. **Broker**:
   - 老系统的 `broker` 表 → 新系统的 `NON_DIRECT_PAYMENT` brokers
   - 老系统的 `sub_broker` 表 → 新系统的 `DIRECT_PAYMENT` brokers
   - **重要**: `sub_broker` 的 `bsb_number` 和 `account_number` 直接映射到 `bankAccountBsb` 和 `bankAccountNumber` 字段（不放入 extra_info）
3. **类型判断**: 根据 `sub_broker_id` 和 `broker_group_id` 判断 `DIRECT_PAYMENT` 或 `NON_DIRECT_PAYMENT`
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
