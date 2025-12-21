#!/bin/bash

# Script to fix created_at timestamps in local database
# This fixes MISSING_BROKER_GROUP and MISSING_AGGREGATOR errors
# Usage: ./fix-local-created-at.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fix Local Database created_at Timestamps ===${NC}\n"

# Local Database Configuration
LOCAL_DB_HOST="${LOCAL_DB_HOST:-localhost}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-5432}"
LOCAL_DB_USER="${LOCAL_DB_USER:-postgres}"
LOCAL_DB_NAME="${LOCAL_DB_NAME:-harbourx}"
LOCAL_DB_PASS="${LOCAL_DB_PASS:-postgres}"

# Try to load configuration from haimoney/start_env.sh
HAIMONEY_ENV_FILE="${HAIMONEY_ENV_FILE:-../../haimoney/start_env.sh}"
if [ -f "$HAIMONEY_ENV_FILE" ]; then
    echo -e "${YELLOW}Loading configuration from $HAIMONEY_ENV_FILE...${NC}"
    set -a
    source "$HAIMONEY_ENV_FILE" 2>/dev/null || true
    set +a
    # Re-read after sourcing
    LOCAL_DB_HOST="${LOCAL_DB_HOST:-${DB_HOST:-localhost}}"
    LOCAL_DB_PORT="${LOCAL_DB_PORT:-${DB_PORT:-5432}}"
    LOCAL_DB_USER="${LOCAL_DB_USER:-${DB_USER:-postgres}}"
    LOCAL_DB_NAME="${LOCAL_DB_NAME:-${DB_NAME:-harbourx}}"
    LOCAL_DB_PASS="${LOCAL_DB_PASS:-${DB_PW:-postgres}}"
fi

echo -e "${GREEN}Local Database Configuration:${NC}"
echo "  Host: $LOCAL_DB_HOST"
echo "  Port: $LOCAL_DB_PORT"
echo "  User: $LOCAL_DB_USER"
echo "  Database: $LOCAL_DB_NAME"
echo ""

# Test database connection
echo -e "${YELLOW}Testing database connection...${NC}"
if ! PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to local database${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Database connection successful${NC}\n"

# Fix broker_group_brokers.created_at and deleted_at
echo -e "${YELLOW}Step 1: Fixing broker_group_brokers.created_at and deleted_at...${NC}"
set +e  # 允许 UPDATE 返回 0 行更新（无 loans 数据时）

# 先检查有多少需要修复的
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
BEFORE_FIX_BGB=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM broker_group_brokers bgb WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_id = bgb.broker_id 
    AND l.settled_date IS NOT NULL 
    AND (
        bgb.created_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
        OR (
            bgb.deleted_at IS NOT NULL 
            AND bgb.deleted_at <= (
                (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
            )
        )
    )
);
" 2>/dev/null | tr -d ' ')

# Fix created_at
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
# 修复所有有 loans 的 broker_group_brokers，确保 created_at 早于最早的 loan settled_date
# 无论 created_at 是否已经正确，都重新设置以确保正确
CREATED_AT_UPDATED=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
UPDATE broker_group_brokers bgb
SET created_at = (
    SELECT (
        (MIN(l.settled_date)::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        - INTERVAL '1 day'
    )
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
)
WHERE EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
);
SELECT COUNT(*) FROM broker_group_brokers bgb WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_id = bgb.broker_id 
    AND l.settled_date IS NOT NULL 
    AND bgb.created_at > (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
" 2>/dev/null | tail -1 | tr -d ' ')

# Fix deleted_at (set to NULL if it's blocking valid loans)
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
DELETED_AT_FIXED=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
UPDATE broker_group_brokers bgb
SET deleted_at = NULL
WHERE bgb.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_id = bgb.broker_id
    AND l.settled_date IS NOT NULL
    AND bgb.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND bgb.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
SELECT COUNT(*) FROM broker_group_brokers bgb WHERE bgb.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_id = bgb.broker_id 
    AND l.settled_date IS NOT NULL 
    AND bgb.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
" 2>/dev/null | tail -1 | tr -d ' ')

# 验证修复后的状态
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
AFTER_FIX_BGB=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM broker_group_brokers bgb WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_id = bgb.broker_id 
    AND l.settled_date IS NOT NULL 
    AND (
        bgb.created_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
        OR (
            bgb.deleted_at IS NOT NULL 
            AND bgb.deleted_at <= (
                (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
            )
        )
    )
);
" 2>/dev/null | tr -d ' ')

BROKER_GROUP_BROKERS_VALID=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM broker_group_brokers bgb WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_id = bgb.broker_id 
    AND l.settled_date IS NOT NULL 
    AND bgb.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND (
        bgb.deleted_at IS NULL 
        OR bgb.deleted_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
    )
);
" 2>/dev/null | tr -d ' ')

set -e

if [ -z "$BEFORE_FIX_BGB" ]; then
    BEFORE_FIX_BGB="0"
fi
if [ -z "$CREATED_AT_UPDATED" ]; then
    CREATED_AT_UPDATED="0"
fi
if [ -z "$CREATED_AT_FIXED" ]; then
    CREATED_AT_FIXED="0"
fi
if [ -z "$DELETED_AT_FIXED" ]; then
    DELETED_AT_FIXED="0"
fi
if [ -z "$AFTER_FIX_BGB" ]; then
    AFTER_FIX_BGB="0"
fi
if [ -z "$BROKER_GROUP_BROKERS_VALID" ]; then
    BROKER_GROUP_BROKERS_VALID="0"
fi

echo -e "${GREEN}✓ Updated broker_group_brokers.created_at and deleted_at${NC}"
if [ -z "$CREATED_AT_UPDATED" ]; then
    CREATED_AT_UPDATED="0"
fi
if [ "$BEFORE_FIX_BGB" = "0" ] && [ "$CREATED_AT_UPDATED" = "0" ]; then
    echo -e "  ${YELLOW}⚠ No issues found, no updates needed.${NC}\n"
else
    if [ "$BEFORE_FIX_BGB" != "0" ]; then
        echo -e "  修复前问题数: $BEFORE_FIX_BGB"
    fi
    if [ "$CREATED_AT_UPDATED" != "0" ]; then
        echo -e "  修复 created_at: $CREATED_AT_UPDATED 个绑定（所有有 loans 的绑定）"
    fi
    if [ "$CREATED_AT_FIXED" != "0" ]; then
        echo -e "  剩余问题: $CREATED_AT_FIXED 个"
    fi
    if [ "$DELETED_AT_FIXED" != "0" ]; then
        echo -e "  修复 deleted_at: $DELETED_AT_FIXED 个"
    fi
    echo -e "  修复后问题数: $AFTER_FIX_BGB"
    echo -e "  修复后有效绑定: $BROKER_GROUP_BROKERS_VALID\n"
fi

# Fix aggregator_broker_groups.created_at and deleted_at
echo -e "${YELLOW}Step 2: Fixing aggregator_broker_groups.created_at and deleted_at...${NC}"
set +e  # 允许 UPDATE 返回 0 行更新（无 loans 数据时）

# 先检查有多少需要修复的
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
BEFORE_FIX=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM aggregator_broker_groups abg WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_group_id = abg.broker_group_id 
    AND l.settled_date IS NOT NULL 
    AND l.broker_group_id IS NOT NULL
    AND (
        abg.created_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
        OR (
            abg.deleted_at IS NOT NULL 
            AND abg.deleted_at <= (
                (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
            )
        )
    )
);
" 2>/dev/null | tr -d ' ')

# 统计需要修复 created_at 的数量
CREATED_AT_NEEDS_FIX=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM aggregator_broker_groups abg WHERE EXISTS (
    SELECT 1 FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
    AND abg.created_at > (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
" 2>/dev/null | tr -d ' ')

# Fix created_at
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
# 修复所有有 loans 的 aggregator_broker_groups，确保 created_at 早于最早的 loan settled_date
# 无论 created_at 是否已经正确，都重新设置以确保正确
CREATED_AT_UPDATED=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
UPDATE aggregator_broker_groups abg
SET created_at = (
    SELECT (
        (MIN(l.settled_date)::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        - INTERVAL '1 day'
    )
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
)
WHERE EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
);
SELECT COUNT(*) FROM aggregator_broker_groups abg WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_group_id = abg.broker_group_id 
    AND l.settled_date IS NOT NULL 
    AND l.broker_group_id IS NOT NULL
);
" 2>/dev/null | tail -1 | tr -d ' ')

# 统计需要修复 deleted_at 的数量
DELETED_AT_NEEDS_FIX=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM aggregator_broker_groups abg WHERE abg.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
    AND abg.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND abg.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
" 2>/dev/null | tr -d ' ')

# Fix deleted_at (set to NULL if it's blocking valid loans)
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
UPDATE aggregator_broker_groups abg
SET deleted_at = NULL
WHERE abg.deleted_at IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.broker_group_id = abg.broker_group_id
    AND l.settled_date IS NOT NULL
    AND l.broker_group_id IS NOT NULL
    AND abg.deleted_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND abg.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
);
" 2>/dev/null > /dev/null

# 验证修复后的状态
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
AGGREGATOR_BROKER_GROUPS_VALID=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM aggregator_broker_groups abg WHERE EXISTS (
    SELECT 1 FROM loans l 
    WHERE l.broker_group_id = abg.broker_group_id 
    AND l.settled_date IS NOT NULL 
    AND l.broker_group_id IS NOT NULL
    AND abg.created_at <= (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    AND (
        abg.deleted_at IS NULL 
        OR abg.deleted_at > (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
    )
);
" 2>/dev/null | tr -d ' ')

set -e

if [ -z "$BEFORE_FIX" ]; then
    BEFORE_FIX="0"
fi
if [ -z "$CREATED_AT_NEEDS_FIX" ]; then
    CREATED_AT_NEEDS_FIX="0"
fi
if [ -z "$DELETED_AT_NEEDS_FIX" ]; then
    DELETED_AT_NEEDS_FIX="0"
fi
if [ -z "$AGGREGATOR_BROKER_GROUPS_VALID" ]; then
    AGGREGATOR_BROKER_GROUPS_VALID="0"
fi

echo -e "${GREEN}✓ Updated aggregator_broker_groups.created_at and deleted_at${NC}"
if [ -z "$CREATED_AT_UPDATED" ]; then
    CREATED_AT_UPDATED="0"
fi
if [ "$BEFORE_FIX" = "0" ] && [ "$CREATED_AT_UPDATED" = "0" ]; then
    echo -e "  ${YELLOW}⚠ No issues found, no updates needed.${NC}\n"
else
    if [ "$BEFORE_FIX" != "0" ]; then
        echo -e "  修复前问题数: $BEFORE_FIX"
    fi
    if [ "$CREATED_AT_UPDATED" != "0" ]; then
        echo -e "  修复 created_at: $CREATED_AT_UPDATED 个绑定（所有有 loans 的绑定）"
    fi
    if [ "$CREATED_AT_NEEDS_FIX" != "0" ]; then
        echo -e "  需要修复 created_at: $CREATED_AT_NEEDS_FIX 个"
    fi
    if [ "$DELETED_AT_NEEDS_FIX" != "0" ]; then
        echo -e "  修复 deleted_at: $DELETED_AT_NEEDS_FIX 个"
    fi
    echo -e "  修复后有效绑定: $AGGREGATOR_BROKER_GROUPS_VALID\n"
fi

# Validation
echo -e "${YELLOW}Step 3: Validating fixes...${NC}"

# Check broker_group_brokers
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
BROKER_GROUP_BROKERS_ISSUES=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM loans l 
INNER JOIN broker_group_brokers bgb ON l.broker_id = bgb.broker_id 
WHERE l.settled_date IS NOT NULL 
AND l.broker_id IS NOT NULL 
AND (
    bgb.created_at > (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    OR (
        bgb.deleted_at IS NOT NULL 
        AND bgb.deleted_at <= (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
    )
);
" 2>/dev/null | tr -d ' ')

# Check aggregator_broker_groups
# 注意：后端使用 settled_date 的中午 12 点（悉尼时间）作为查询时间
AGGREGATOR_BROKER_GROUPS_ISSUES=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -A -F'|' -c "
SELECT COUNT(*) FROM loans l 
INNER JOIN aggregator_broker_groups abg ON l.broker_group_id = abg.broker_group_id 
WHERE l.settled_date IS NOT NULL 
AND l.broker_group_id IS NOT NULL 
AND (
    abg.created_at > (
        (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
    )
    OR (
        abg.deleted_at IS NOT NULL 
        AND abg.deleted_at <= (
            (l.settled_date::timestamp with time zone AT TIME ZONE 'Australia/Sydney' + INTERVAL '12 hours')::timestamp with time zone
        )
    )
);
" 2>/dev/null | tr -d ' ')

if [ "$BROKER_GROUP_BROKERS_ISSUES" = "0" ] && [ "$AGGREGATOR_BROKER_GROUPS_ISSUES" = "0" ]; then
    echo -e "${GREEN}✓ Validation passed: All created_at timestamps are correctly set${NC}"
    echo -e "${GREEN}✓ No remaining issues with broker_group_brokers or aggregator_broker_groups${NC}\n"
else
    echo -e "${YELLOW}⚠ Validation found some remaining issues:${NC}"
    echo "  broker_group_brokers issues: $BROKER_GROUP_BROKERS_ISSUES"
    echo "  aggregator_broker_groups issues: $AGGREGATOR_BROKER_GROUPS_ISSUES"
    echo ""
fi

echo -e "${GREEN}=== Fix Complete ===${NC}"
echo ""
echo "Summary:"
echo "  - broker_group_brokers: Fixed created_at and deleted_at timestamps"
echo "  - aggregator_broker_groups: Fixed created_at and deleted_at timestamps"
echo ""
echo "The MISSING_BROKER_GROUP and MISSING_AGGREGATOR errors should now be resolved."

