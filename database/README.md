# MEC Database

This directory contains the database schema and seed data for the MEC (Metering, Entitlements, Controls) service.

## Files

| File | Description |
|------|-------------|
| `schema.sql` | Complete DDL - tables, indexes, views, functions, triggers |
| `seed.sql` | Lookup table data and sample plans |

## Quick Start

### Option 1: Using Docker Compose (Recommended)

```bash
# From project root
docker-compose up -d

# Database is automatically initialized with schema and seed data
```

### Option 2: Manual Setup

```bash
# Create database
createdb mec

# Apply schema
psql -d mec -f database/schema.sql

# Load seed data
psql -d mec -f database/seed.sql
```

## Schema Overview

### Layer 0: Foundation
- `account_types` - User, organization, team
- `accounts` - Customer accounts with hierarchy
- `units` - Measurement units (count, hours, etc.)
- `resource_types` - What can be metered/entitled
- `limit_kinds` - Cumulative, concurrency, inventory, time_access
- `window_types` - Calendar month, billing cycle, rolling
- `limit_actions` - Block, warn, grace, overage

### Layer 0.5: Plans
- `plans` - Commercial packages
- `plan_entitlement_templates` - What each plan grants

### Layer 1: Metering
- `consumption_ledger` - Append-only usage log
- `consumption_event_details` - Event metadata

### Layer 2: Entitlements
- `entitlements` - Active customer entitlements
- `entitlement_conditions` - Conditional rules
- `entitlements_audit` - Change history

### Layer 3: Controls
- `control_rules` - What happens at limits
- `concurrency_leases` - Floating license tracking
- `control_decisions_log` - Access decision audit

## Key Functions

| Function | Description |
|----------|-------------|
| `fn_check_entitlement()` | Check if action is allowed |
| `fn_acquire_lease()` | Acquire concurrency lease |
| `fn_release_lease()` | Release a lease |
| `fn_meter_consumption()` | Record usage event |
| `fn_provision_plan_entitlements()` | Create entitlements from plan |

## Example Usage

```sql
-- Check if user can run a benchmark
SELECT * FROM fn_check_entitlement(
    'account-uuid'::UUID,
    'benchmark_runs',
    NULL,  -- no scope
    1      -- requesting 1 run
);

-- Record consumption
SELECT fn_meter_consumption(
    'run_12345',           -- idempotency key
    'account-uuid'::UUID,
    'benchmark_runs',
    1,
    'count'
);

-- Provision a plan for new customer
SELECT fn_provision_plan_entitlements(
    'account-uuid'::UUID,
    'pro',
    NOW()
);
```

## Connecting

```
Host: localhost (or db in Docker)
Port: 5432
Database: mec
User: mec
Password: (see .env)
```
