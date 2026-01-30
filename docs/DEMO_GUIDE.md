# MEC Service Demo Guide

A step-by-step walkthrough of the MEC (Metering, Entitlements, Controls) system for demos and presentations.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Understanding the Architecture](#2-understanding-the-architecture)
3. [Demo Scenario: SaaS Benchmark Platform](#3-demo-scenario-saas-benchmark-platform)
4. [Step-by-Step Demo](#4-step-by-step-demo)
   - [Step 1: Health Check](#step-1-health-check)
   - [Step 2: View Available Plans](#step-2-view-available-plans)
   - [Step 3: Create a Customer Account](#step-3-create-a-customer-account)
   - [Step 4: Provision a Plan](#step-4-provision-a-plan)
   - [Step 5: Check Entitlements](#step-5-check-entitlements)
   - [Step 6: Control Check (Can they do this?)](#step-6-control-check-can-they-do-this)
   - [Step 7: Record Usage (Metering)](#step-7-record-usage-metering)
   - [Step 8: Check Usage After Consumption](#step-8-check-usage-after-consumption)
   - [Step 9: Concurrency Control (Floating Licenses)](#step-9-concurrency-control-floating-licenses)
   - [Step 10: Hitting the Limit](#step-10-hitting-the-limit)
5. [Schema Reference](#5-schema-reference)
6. [Common Demo Scenarios](#6-common-demo-scenarios)

---

## 1. Quick Start

```bash
# Start all services
cd /home/ubuntu/mec-service/docker
docker compose up -d

# Verify everything is running
curl http://localhost:8000/health
# Expected: {"status": "healthy"}
```

**Services Running:**
| Service | Port | Purpose |
|---------|------|---------|
| nginx | 8000 | API Gateway (entry point) |
| PostgREST | 3000 | Auto-generated REST API |
| FastAPI | 8005 | Webhooks (Stripe, Auth0) |
| PostgreSQL | 5432 | Database with all business logic |
| Redis | 6379 | Caching (optional) |

---

## 2. Understanding the Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Your Application                         │
│              (Insights API, Dashboard, etc.)                  │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    MEC Service (:8000)                        │
│                                                               │
│   "Can this user run a benchmark?"  →  allow/deny            │
│   "Record 1 benchmark run"          →  logged                │
│   "How many runs left?"             →  75 remaining          │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                      PostgreSQL                               │
│                                                               │
│   Tables: accounts, entitlements, consumption_ledger, ...    │
│   Functions: fn_check_entitlement, fn_meter_consumption, ... │
└──────────────────────────────────────────────────────────────┘
```

**Key Concepts:**

| Concept | What it means | Example |
|---------|---------------|---------|
| **Metering** | Recording what was used | "User ran 5 benchmarks" |
| **Entitlement** | What a user is allowed | "User can run 100 benchmarks/month" |
| **Control** | Allow/deny decision | "User has 55 left → ALLOW" |

---

## 3. Demo Scenario: SaaS Benchmark Platform

**Story:** You're building a SaaS platform where customers can run AI model benchmarks.

**Pricing Plans:**

| Plan | Monthly Price | Benchmark Runs | Concurrent Users | GPU Hours |
|------|---------------|----------------|------------------|-----------|
| Trial | Free | 50 | 2 | 5 |
| Starter | $99 | 100 | 3 | 25 |
| Pro | $299 | 500 | 10 | 100 |
| Enterprise | Custom | Unlimited | Unlimited | Unlimited |

**What MEC Does:**
1. ✅ Tracks how many benchmarks each customer runs
2. ✅ Enforces limits (blocks when quota exhausted)
3. ✅ Manages concurrent user sessions (floating licenses)
4. ✅ Provides real-time usage data for dashboards

---

## 4. Step-by-Step Demo

### Step 1: Health Check

**Command:**
```bash
curl http://localhost:8000/health
```

**Expected Response:**
```json
{"status": "healthy"}
```

**What's happening:**
- nginx receives the request
- FastAPI's health endpoint responds
- Confirms all services are running

**Why it matters:**
- First thing to check in any demo
- Proves the system is operational

---

### Step 2: View Available Plans

**Command:**
```bash
curl -s http://localhost:8000/api/plans | jq .
```

**Expected Response:**
```json
[
  {
    "plan_id": "trial-14d",
    "plan_name": "14-Day Free Trial",
    "is_trial": true,
    "trial_days": 14
  },
  {
    "plan_id": "starter",
    "plan_name": "Starter",
    "is_trial": false
  },
  {
    "plan_id": "pro",
    "plan_name": "Pro",
    "is_trial": false
  },
  {
    "plan_id": "enterprise",
    "plan_name": "Enterprise",
    "is_trial": false
  }
]
```

**What's happening:**
- PostgREST auto-generates `GET /api/plans` from the `plans` table
- No code written - just database table → REST API

**Schema Reference:** `schema.sql` lines 115-128
```sql
CREATE TABLE plans (
    plan_id             VARCHAR(64)     PRIMARY KEY,
    plan_name           VARCHAR(128)    NOT NULL,
    is_trial            BOOLEAN         NOT NULL DEFAULT FALSE,
    trial_days          INT,
    ...
);
```

**Why it matters:**
- Shows the commercial packaging layer
- Plans define what customers get when they subscribe

---

### Step 3: Create a Customer Account

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/accounts \
  -H "Content-Type: application/json" \
  -d '{
    "account_type_code": "organization",
    "display_name": "Acme Corp",
    "external_id": "stripe_cus_abc123",
    "email": "admin@acme.com"
  }' | jq .
```

**Expected Response:**
```json
{
  "account_id": "a1b2c3d4-...",
  "display_name": "Acme Corp",
  "status": "active",
  ...
}
```

**What's happening:**
- Creates a new account record
- `external_id` links to Stripe customer ID (for billing integration)
- `account_type_code` is "organization" (can have child user accounts)

**Schema Reference:** `schema.sql` lines 26-44
```sql
CREATE TABLE accounts (
    account_id          UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_type_code   VARCHAR(32)     NOT NULL REFERENCES account_types,
    external_id         VARCHAR(128),   -- Links to Stripe/Auth0
    display_name        VARCHAR(255)    NOT NULL,
    email               VARCHAR(255),
    status              VARCHAR(16)     NOT NULL DEFAULT 'active',
    ...
);
```

**Why it matters:**
- Every customer needs an account
- `external_id` enables integration with billing/auth systems
- Account hierarchy supports org → team → user structures

---

### Step 4: Provision a Plan

**Command:**
```bash
# Replace ACCOUNT_ID with the UUID from Step 3
curl -s -X POST http://localhost:8000/api/rpc/provision_plan \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_plan_id": "starter"
  }' | jq .
```

**Expected Response:**
```json
5
```
(Number of entitlements created)

**What's happening:**
1. Looks up the "starter" plan templates
2. Creates 5 entitlements for this account:
   - 100 benchmark runs/month
   - 3 concurrent users
   - 25 GPU hours/month
   - 2 server configs
   - 10 server instances

**Schema Reference:** `schema.sql` lines 871-911
```sql
CREATE OR REPLACE FUNCTION fn_provision_plan_entitlements(
    p_account_id    UUID,
    p_plan_id       VARCHAR(64),
    p_start_date    TIMESTAMPTZ DEFAULT NOW()
)
RETURNS INT
...
-- Loops through plan_entitlement_templates
-- Creates entitlements for each template
```

**Why it matters:**
- **This is the magic!** One API call sets up all quotas
- When Stripe webhook fires "subscription.created", call this function
- Customer immediately has all their plan limits configured

---

### Step 5: Check Entitlements

**Command:**
```bash
curl -s "http://localhost:8000/api/entitlements?account_id=eq.ACCOUNT_ID" | jq '.[] | {resource_type_code, quantity_allowed, limit_kind_code}'
```

**Expected Response:**
```json
{"resource_type_code": "benchmark_runs", "quantity_allowed": 100, "limit_kind_code": "cumulative"}
{"resource_type_code": "concurrent_users", "quantity_allowed": 3, "limit_kind_code": "concurrency"}
{"resource_type_code": "gpu_hours", "quantity_allowed": 25, "limit_kind_code": "cumulative"}
{"resource_type_code": "server_configs", "quantity_allowed": 2, "limit_kind_code": "inventory"}
{"resource_type_code": "server_instances", "quantity_allowed": 10, "limit_kind_code": "inventory"}
```

**What's happening:**
- Queries all entitlements for this account
- Shows what resources they can use and how much

**Schema Reference:** `schema.sql` lines 201-238
```sql
CREATE TABLE entitlements (
    entitlement_id      UUID            PRIMARY KEY,
    account_id          UUID            NOT NULL REFERENCES accounts,
    resource_type_code  VARCHAR(64)     NOT NULL,  -- What resource
    limit_kind_code     VARCHAR(32)     NOT NULL,  -- How to count
    quantity_allowed    NUMERIC(18,6),             -- The limit
    window_type_code    VARCHAR(32),               -- Reset period
    ...
);
```

**Limit Kinds Explained:**

| Kind | Meaning | Example |
|------|---------|---------|
| `cumulative` | Adds up over time window | "100 runs per month" |
| `concurrency` | Max simultaneous | "3 users at once" |
| `inventory` | Total items owned | "10 server configs" |
| `time_access` | Valid until date | "14-day trial" |

---

### Step 6: Control Check (Can they do this?)

**This is the most important API call!**

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs",
    "p_requested_qty": 1
  }' | jq .
```

**Expected Response:**
```json
[
  {
    "decision": "allow",
    "reason": "Within entitlement",
    "entitlement_id": "...",
    "quantity_allowed": 100,
    "quantity_used": 0,
    "quantity_remaining": 100,
    "percent_used": 0,
    "limit_kind": "cumulative"
  }
]
```

**What's happening:**
1. Find the applicable entitlement for this account + resource
2. Calculate current usage in the time window
3. Apply control rules (warn thresholds, grace periods)
4. Return allow/deny/warn decision

**Schema Reference:** `schema.sql` lines 611-740
```sql
CREATE OR REPLACE FUNCTION fn_check_entitlement(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_requested_qty     NUMERIC DEFAULT 1
)
RETURNS TABLE (
    decision            VARCHAR(16),    -- 'allow', 'deny', 'warn'
    reason              VARCHAR(255),
    quantity_allowed    NUMERIC,
    quantity_used       NUMERIC,
    quantity_remaining  NUMERIC,
    percent_used        NUMERIC,
    ...
)
```

**Decision Values:**

| Decision | Meaning | Your App Should... |
|----------|---------|-------------------|
| `allow` | Good to go | Proceed with action |
| `warn` | Near limit (80%+) | Show warning, but allow |
| `deny` | Limit reached | Block action, show upgrade prompt |
| `grace` | Over limit, but grace period | Allow, but notify |
| `overage` | Over limit, will be billed | Allow, track for billing |

**Why it matters:**
- **Call this BEFORE every billable action**
- < 50ms response time (database function, no ORM)
- Returns all info needed for UI (remaining, percent, etc.)

---

### Step 7: Record Usage (Metering)

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/meter_consumption \
  -H "Content-Type: application/json" \
  -d '{
    "p_idempotency_key": "benchmark_run_12345",
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs",
    "p_quantity": 1,
    "p_unit_code": "count"
  }' | jq .
```

**Expected Response:**
```json
"e1f2g3h4-..."
```
(Event ID of the recorded consumption)

**What's happening:**
1. Validates the unit is allowed for this resource type
2. Creates an immutable record in the consumption ledger
3. Returns the event ID for your records

**Schema Reference:** `schema.sql` lines 155-182
```sql
CREATE TABLE consumption_ledger (
    event_id            UUID            PRIMARY KEY,
    idempotency_key     VARCHAR(255)    NOT NULL UNIQUE,  -- Prevents duplicates!
    account_id          UUID            NOT NULL,
    resource_type_code  VARCHAR(64)     NOT NULL,
    quantity            NUMERIC(18,6)   NOT NULL,
    occurred_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    is_correction       BOOLEAN         NOT NULL DEFAULT FALSE,
    ...
);
```

**Key Features:**

| Feature | Why |
|---------|-----|
| `idempotency_key` | Same key = same event (safe retries) |
| Append-only | Can't edit/delete (audit compliance) |
| `is_correction` | Mistakes fixed via compensating events |

**Schema Reference - Append-Only Trigger:** `schema.sql` lines 932-946
```sql
CREATE OR REPLACE FUNCTION fn_prevent_ledger_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Consumption ledger is append-only. Cannot update.';
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Consumption ledger is append-only. Cannot delete.';
    END IF;
END;
$$;
```

**Why it matters:**
- **Call this AFTER every billable action completes**
- Idempotency means safe to retry on network failures
- Immutable ledger = audit trail for compliance

---

### Step 8: Check Usage After Consumption

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs"
  }' | jq '.[0] | {decision, quantity_used, quantity_remaining, percent_used}'
```

**Expected Response:**
```json
{
  "decision": "allow",
  "quantity_used": 1,
  "quantity_remaining": 99,
  "percent_used": 1
}
```

**What's happening:**
- Same check as Step 6, but now shows 1 used
- The metered consumption is reflected immediately

**Why it matters:**
- Real-time usage tracking
- Perfect for dashboards showing "X of Y used"

---

### Step 9: Concurrency Control (Floating Licenses)

**Scenario:** Your plan allows 3 concurrent users. Let's manage that.

#### 9a. Acquire a Session (User Logs In)

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/acquire_lease \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "concurrent_users",
    "p_session_token": "user_alice_session_001",
    "p_ttl_minutes": 60
  }' | jq .
```

**Expected Response:**
```json
[
  {
    "success": true,
    "lease_id": "l1m2n3o4-...",
    "decision": "allow",
    "reason": "Within entitlement",
    "expires_at": "2026-01-30T12:00:00Z"
  }
]
```

**What's happening:**
1. Checks if there's room for another concurrent user
2. Creates a "lease" (like a session lock)
3. Lease expires in 60 minutes unless renewed

**Schema Reference:** `schema.sql` lines 309-332
```sql
CREATE TABLE concurrency_leases (
    lease_id            UUID            PRIMARY KEY,
    account_id          UUID            NOT NULL,
    resource_type_code  VARCHAR(64)     NOT NULL,
    session_token       VARCHAR(255),    -- Your session ID
    acquired_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ     NOT NULL,
    released_at         TIMESTAMPTZ,     -- NULL = still active
    ...
);
```

#### 9b. Check Concurrent Usage

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "concurrent_users"
  }' | jq '.[0] | {decision, quantity_used, quantity_remaining}'
```

**Expected Response:**
```json
{
  "decision": "allow",
  "quantity_used": 1,
  "quantity_remaining": 2
}
```

#### 9c. Release Session (User Logs Out)

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/release_lease \
  -H "Content-Type: application/json" \
  -d '{
    "p_lease_id": "LEASE_ID_FROM_9a"
  }' | jq .
```

**Expected Response:**
```json
true
```

**Why it matters:**
- Floating licenses without expensive license servers
- Auto-expire handles crashed clients (no stuck sessions)
- `session_token` lets you find/manage specific sessions

---

### Step 10: Hitting the Limit

**Let's see what happens when a user exceeds their quota.**

#### 10a. Use Up the Quota

**Command:**
```bash
# Record 99 more benchmark runs (we already did 1)
curl -s -X POST http://localhost:8000/api/rpc/meter_consumption \
  -H "Content-Type: application/json" \
  -d '{
    "p_idempotency_key": "bulk_usage_demo",
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs",
    "p_quantity": 99,
    "p_unit_code": "count"
  }'
```

#### 10b. Check - Should Show Warning

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs"
  }' | jq '.[0] | {decision, reason, quantity_used, percent_used}'
```

**Expected Response:**
```json
{
  "decision": "warn",
  "reason": "Usage at 100.0% of limit",
  "quantity_used": 100,
  "percent_used": 100
}
```

**What's happening:**
- Control rule kicks in at 80% → warn
- Still allows the action, but signals "almost out"

**Schema Reference - Control Rules:** `schema.sql` lines 272-296
```sql
CREATE TABLE control_rules (
    rule_id             UUID            PRIMARY KEY,
    resource_type_code  VARCHAR(64)     NOT NULL,
    limit_kind_code     VARCHAR(32)     NOT NULL,
    limit_action_code   VARCHAR(32)     NOT NULL,  -- 'block', 'warn', 'grace', 'overage'
    warn_at_percent     NUMERIC(5,2),              -- e.g., 80.00
    grace_quantity      NUMERIC(18,6),             -- Extra allowance
    ...
);
```

#### 10c. Try One More - Should Deny

**Command:**
```bash
curl -s -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -d '{
    "p_account_id": "ACCOUNT_ID",
    "p_resource_type": "benchmark_runs",
    "p_requested_qty": 1
  }' | jq '.[0] | {decision, reason}'
```

**Expected Response:**
```json
{
  "decision": "block",
  "reason": "Limit reached"
}
```

**What's happening:**
- No quota remaining
- Control rule says "block" when limit reached
- Your app should show "Upgrade to Pro for more runs"

---

## 5. Schema Reference

### Tables by Layer

```
LAYER 0: Foundation
├── account_types      (line 16)   - Types of accounts
├── accounts           (line 26)   - Customer accounts
├── units              (line 49)   - Measurement units
├── resource_types     (line 59)   - What can be metered
├── limit_kinds        (line 84)   - How limits work
├── window_types       (line 93)   - Time windows
└── limit_actions      (line 102)  - What happens at limits

LAYER 0.5: Plans
├── plans              (line 115)  - Commercial packages
└── plan_entitlement_templates (line 133) - What each plan includes

LAYER 1: Metering
├── consumption_ledger (line 155)  - Usage events (append-only)
└── consumption_event_details (line 187) - Extra metadata

LAYER 2: Entitlements
├── entitlements       (line 201)  - What accounts can use
├── entitlement_conditions (line 243) - Additional conditions
└── entitlements_audit (line 253)  - Change history

LAYER 3: Controls
├── control_rules      (line 272)  - What happens at boundaries
├── concurrency_leases (line 309)  - Floating licenses
└── control_decisions_log (line 337) - Decision audit trail
```

### Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `fn_check_entitlement` | 611 | Main control check |
| `fn_meter_consumption` | 820 | Record usage |
| `fn_acquire_lease` | 743 | Get concurrency slot |
| `fn_release_lease` | 796 | Release slot |
| `fn_provision_plan_entitlements` | 871 | Assign plan |
| `fn_get_usage` | 463 | Calculate usage |
| `fn_get_window_boundaries` | 410 | Time window math |

---

## 6. Common Demo Scenarios

### Scenario A: New Customer Signup

```bash
# 1. Stripe webhook fires → FastAPI receives it
# 2. Create account
POST /api/accounts
{"external_id": "stripe_cus_xxx", "display_name": "New Customer"}

# 3. Provision their plan
POST /api/rpc/provision_plan
{"p_account_id": "...", "p_plan_id": "starter"}

# Done! Customer has all their quotas set up
```

### Scenario B: Before Running a Benchmark

```bash
# 1. Check if allowed
POST /api/rpc/check_entitlement
{"p_account_id": "...", "p_resource_type": "benchmark_runs"}

# 2. If "allow" → run the benchmark
# 3. After success, record it
POST /api/rpc/meter_consumption
{"p_idempotency_key": "run_123", "p_account_id": "...", "p_resource_type": "benchmark_runs", "p_quantity": 1}
```

### Scenario C: User Dashboard

```bash
# Get all usage stats for display
POST /api/rpc/check_entitlement → benchmark_runs
POST /api/rpc/check_entitlement → gpu_hours
POST /api/rpc/check_entitlement → concurrent_users

# Display: "45/100 benchmark runs used this month"
```

### Scenario D: Plan Upgrade

```bash
# 1. Expire old entitlements
PATCH /api/entitlements?account_id=eq.xxx
{"status": "expired"}

# 2. Provision new plan
POST /api/rpc/provision_plan
{"p_account_id": "...", "p_plan_id": "pro"}
```

---

## Quick Reference Card

### Most Used Endpoints

| Action | Endpoint | When to Use |
|--------|----------|-------------|
| **Can they?** | `POST /api/rpc/check_entitlement` | Before any billable action |
| **Record usage** | `POST /api/rpc/meter_consumption` | After action completes |
| **Login** | `POST /api/rpc/acquire_lease` | User session start |
| **Logout** | `POST /api/rpc/release_lease` | User session end |
| **New customer** | `POST /api/rpc/provision_plan` | After subscription created |

### Response Decisions

| Decision | Meaning | UI Action |
|----------|---------|-----------|
| `allow` | ✅ Proceed | Green light |
| `warn` | ⚠️ Near limit | Show warning banner |
| `deny` | ❌ Blocked | Show upgrade prompt |
| `grace` | 🟡 Grace period | Allow but notify |
| `overage` | 💰 Will be billed | Allow, show cost |

---

*Created for MEC Service Demo*
*Last Updated: January 2026*
