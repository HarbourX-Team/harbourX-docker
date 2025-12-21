# 计算完成后修复 created_at 问题

## 问题描述

当上传 RCTI 文件并点击计算后，如果系统创建了新的 `broker_group_brokers` 或 `aggregator_broker_groups` 绑定，这些绑定的 `created_at` 会被设置为当前时间。

如果 RCTI 文件中的 loan 的 `settled_date` 是过去的日期，那么新创建的绑定的 `created_at` 会晚于 `settled_date + 12h`，导致查询时找不到绑定，从而报错 `MISSING_BROKER_GROUP` 或 `MISSING_AGGREGATOR`。

## 解决方案

在计算完成后，运行修复脚本来自动修复所有 `created_at` 问题：

```bash
cd /Users/yafengzhu/Desktop/harbourX/migrationScripts
./fix-local-created-at.sh
```

## 使用步骤

1. 运行 `./migrate.sh local` 迁移数据
2. 上传 RCTI 文件
3. 点击计算
4. **计算完成后，运行修复脚本**：
   ```bash
   cd /Users/yafengzhu/Desktop/harbourX/migrationScripts
   ./fix-local-created-at.sh
   ```
5. 重新计算 commission transactions（如果需要）

## 自动化方案（可选）

如果你希望每次计算完成后自动运行修复脚本，可以：

1. 创建一个监控脚本，定期检查是否有新的绑定需要修复
2. 或者在后端计算完成后自动调用修复脚本（需要后端支持）

## 验证修复

运行验证脚本检查修复结果：

```bash
./verify-created-at.sh local
```

或者运行诊断脚本：

```bash
./diagnose-missing-broker-group.sh
./diagnose-missing-aggregator.sh
```
