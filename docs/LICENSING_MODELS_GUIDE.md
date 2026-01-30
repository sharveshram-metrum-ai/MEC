# MEC Licensing & Pricing Models Guide

This document shows how the MEC schema supports various licensing and pricing models, with SQL examples for each scenario.

---

## Table of Contents

1. [Overview](#overview)
2. [Time-Based Access](#1-time-based-access)
3. [Usage-Based (Pay-As-You-Go)](#2-usage-based-pay-as-you-go)
4. [Seat-Based Licensing](#3-seat-based-licensing)
5. [Inventory Limits](#4-inventory-limits)
6. [Hybrid Plans (SaaS Tiers)](#5-hybrid-plans-saas-tiers)
7. [Advanced Scenarios](#6-advanced-scenarios)
8. [Complete Examples](#7-complete-examples)
9. [What's NOT Supported](#8-whats-not-supported)
10. [Quick Reference](#9-quick-reference)

---

## Overview

### How MEC Models Licensing

| Licensing Model | MEC Concept | Key Fields |
|-----------------|-------------|------------|
| Time-based | `time_access` limit kind | `effective_start`, `effective_end` |
| Usage-based | `cumulative` limit kind | `quantity_allowed`, `window_type_code` |
| Seat-based (named) | `inventory` limit kind | `quantity_allowed` |
| Seat-based (floating) | `concurrency` limit kind | `quantity_allowed` + leases |
| Overage billing | `overage` limit action | `control_rules.limit_action_code` |
| Tiered pricing | Multiple entitlements | `resource_scope` + `priority` |

### Core Tables Used

```
plans                        → Commercial packages
plan_entitlement_templates   → What each plan grants
entitlements                 → Active customer entitlements
control_rules                → What happens at limits
consumption_ledger           → Usage tracking
concurrency_leases           → Floating seat tracking
```

---

## 1. Time-Based Access

### 1.1 Free Trial (14 Days)

```sql
-- Plan definition
INSERT INTO plans (plan_id, namespace_id, plan_name, is_trial, trial_days, status) VALUES
    ('trial-14d', 'metrum-insights', '14-Day Free Trial', TRUE, 14, 'active');

-- Template: Full access for 14 days
INSERT INTO plan_entitlement_templates 
    (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, duration_days) 
VALUES
    ('trial-14d', 'platform_access', 'time_access', NULL, 'days', 14),
    ('trial-14d', 'benchmark_runs', 'cumulative', 50, 'count', 14),
    ('trial-14d', 'gpu_hours', 'cumulative', 10, 'hours', 14);

-- When user signs up for trial:
SELECT fn_provision_plan_entitlements('user-uuid-here'::UUID, 'trial-14d', NOW());
```

### 1.2 Monthly Subscription

```sql
INSERT INTO plans (plan_id, plan_name, external_id, status) VALUES
    ('pro-monthly', 'Pro Monthly', 'stripe_price_pro_monthly', 'active');

INSERT INTO plan_entitlement_templates 
    (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code, duration_days) 
VALUES
    ('pro-monthly', 'platform_access', 'time_access', NULL, 'days', NULL, 30),
    ('pro-monthly', 'benchmark_runs', 'cumulative', 500, 'count', 'calendar_month', NULL),
    ('pro-monthly', 'gpu_hours', 'cumulative', 100, 'hours', 'calendar_month', NULL);
```

---

## 2. Usage-Based (Pay-As-You-Go)

### 2.1 Simple Per-Unit Pricing

```sql
-- Entitlement: Unlimited runs, but we track everything
INSERT INTO entitlements (
    account_id, resource_type_code, limit_kind_code, 
    quantity_allowed, unit_code, window_type_code
) VALUES (
    'customer-uuid', 'benchmark_runs', 'cumulative',
    NULL,  -- NULL = unlimited (pay-as-you-go)
    'count', 'calendar_month'
);

-- Control rule: Always allow, but log for billing
INSERT INTO control_rules (
    resource_type_code, limit_kind_code, limit_action_code
) VALUES (
    'benchmark_runs', 'cumulative', 'overage'
);

-- When run completes, meter it:
SELECT fn_meter_consumption('run_12345', 'customer-uuid'::UUID, 'benchmark_runs', 1, 'count');
```

### 2.2 Included Allowance + Overage

```sql
-- 50 runs included, then $10/run beyond
INSERT INTO plan_entitlement_templates VALUES
    (uuid_generate_v4(), 'starter-50', 'benchmark_runs', NULL, 'cumulative', 50, 'count', 'calendar_month', NULL);

-- Control rule: Allow overage
INSERT INTO control_rules (
    resource_type_code, limit_kind_code, limit_action_code, 
    warn_at_percent, overage_multiplier
) VALUES (
    'benchmark_runs', 'cumulative', 'overage', 80.00, 10.00
);
```

---

## 3. Seat-Based Licensing

### 3.1 Named Users (Inventory Model)

```sql
INSERT INTO entitlements (account_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code) VALUES
    ('org-uuid', 'named_users', 'inventory', 5, 'count');

-- Check if seats available
SELECT * FROM fn_check_entitlement('org-uuid', 'named_users', NULL, 1);

-- Record seat assignment
SELECT fn_meter_consumption('user_abc123_seat', 'org-uuid'::UUID, 'named_users', 1, 'count');
```

### 3.2 Concurrent/Floating Users (Concurrency Model)

```sql
INSERT INTO entitlements (account_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code) VALUES
    ('org-uuid', 'concurrent_users', 'concurrency', 3, 'count');

-- When user logs in:
SELECT * FROM fn_acquire_lease('org-uuid'::UUID, 'concurrent_users', NULL, 'session_token_xyz', 480);

-- When user logs out:
SELECT fn_release_lease('lease-uuid'::UUID);
```

---

## 4. Inventory Limits

```sql
-- Up to 10 server configurations
INSERT INTO entitlements (account_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code) VALUES
    ('org-uuid', 'server_configs', 'inventory', 10, 'count');

-- When creating a config:
SELECT * FROM fn_check_entitlement('org-uuid', 'server_configs', NULL, 1);
SELECT fn_meter_consumption('config_xyz', 'org-uuid', 'server_configs', 1, 'count');
```

---

## 5. Hybrid Plans (SaaS Tiers)

### Starter Plan - $99/month

```sql
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code) VALUES
    ('starter', 'concurrent_users', 'concurrency', 2, 'count', NULL),
    ('starter', 'server_configs', 'inventory', 1, 'count', NULL),
    ('starter', 'benchmark_runs', 'cumulative', 50, 'count', 'calendar_month'),
    ('starter', 'gpu_hours', 'cumulative', 10, 'hours', 'calendar_month');
```

### Pro Plan - $499/month

```sql
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code) VALUES
    ('pro', 'concurrent_users', 'concurrency', 10, 'count', NULL),
    ('pro', 'server_configs', 'inventory', 3, 'count', NULL),
    ('pro', 'benchmark_runs', 'cumulative', 500, 'count', 'calendar_month'),
    ('pro', 'gpu_hours', 'cumulative', 100, 'hours', 'calendar_month');
```

---

## 6. Quick Reference

### Limit Kinds

| Code | Use Case | Example |
|------|----------|---------|
| `cumulative` | Usage that resets per window | 100 runs/month |
| `concurrency` | Simultaneous usage | 5 floating users |
| `inventory` | Count of owned items | 10 server configs |
| `time_access` | Time-bound access | 30-day subscription |

### Window Types

| Code | Resets |
|------|--------|
| `calendar_month` | 1st of each month |
| `billing_cycle` | Subscription anniversary |
| `rolling_30d` | 30 days from any point |
| `none` | Never (lifetime/prepaid) |

### Limit Actions

| Code | Behavior |
|------|----------|
| `block` | Hard deny when limit reached |
| `warn` | Allow but notify |
| `grace` | Allow temporary overage |
| `overage` | Allow and bill for extra |

---

*See full guide for complete examples and advanced scenarios.*
