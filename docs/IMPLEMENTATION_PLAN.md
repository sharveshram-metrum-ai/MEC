# MEC v3 Implementation Plan (Hybrid Architecture)

A production-ready implementation plan for the Metering, Entitlements, and Controls system using PostgREST + FastAPI.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Project Structure](#project-structure)
4. [Implementation Status](#implementation-status)
5. [Phase 1: Foundation (COMPLETE)](#phase-1-foundation-complete)
6. [Phase 2: API Layer (COMPLETE)](#phase-2-api-layer-complete)
7. [Phase 3: Integration (IN PROGRESS)](#phase-3-integration-in-progress)
8. [Phase 4: Testing](#phase-4-testing)
9. [Phase 5: Production Hardening](#phase-5-production-hardening)
10. [API Reference](#api-reference)
11. [Deployment Guide](#deployment-guide)

---

## Executive Summary

### Goal
Build a production-ready MEC (Metering, Entitlements, Controls) microservice that handles:
- **Consumption tracking** (append-only ledger)
- **Entitlement management** (quotas, limits, plans)
- **Access control** (real-time allow/deny decisions)
- **Concurrency management** (floating licenses)

### Architecture Decision
**Hybrid (PostgREST + FastAPI)** chosen over pure FastAPI because:
- 78% less code to maintain
- Better performance (no ORM overhead)
- Business logic already in PostgreSQL functions
- Can still handle webhooks via FastAPI

### Key Principles

| Principle | Implementation |
|-----------|----------------|
| **Immutability** | Append-only ledger, corrections via compensating events |
| **Idempotency** | All writes use idempotency keys |
| **Atomicity** | Critical operations use database functions/transactions |
| **Auditability** | Full audit trail for compliance |
| **Extensibility** | Lookup tables instead of hardcoded values |
| **Performance** | < 50ms control checks via PostgREST |

### Success Criteria

- [x] Database schema with all tables, functions, triggers
- [x] Auto-generated REST API via PostgREST
- [x] Webhook handlers for Stripe/Auth0
- [ ] All control checks complete in < 50ms (p99)
- [ ] Full test coverage
- [ ] Production deployment

---

## Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENTS                                      │
│         (Insights API, Worker Nodes, Admin Dashboard)               │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    nginx (API Gateway) :8000                         │
│                                                                      │
│   • Routing (/api/* → PostgREST, /webhooks/* → FastAPI)            │
│   • Rate limiting (100 req/s API, 10 req/s webhooks)                │
│   • SSL termination (production)                                     │
│   • Response caching (optional)                                      │
└─────────────────────────────────────────────────────────────────────┘
                    │                               │
        /api/*      │                               │    /webhooks/*
                    ▼                               ▼    /admin/*
┌───────────────────────────────┐   ┌─────────────────────────────────┐
│      PostgREST :3000          │   │       FastAPI :8005             │
│                               │   │                                 │
│  Auto-generated REST API      │   │  • Stripe webhook handlers      │
│  from PostgreSQL schema       │   │  • Auth0 user sync              │
│                               │   │  • Bulk admin operations        │
│  Endpoints:                   │   │  • Complex multi-step flows     │
│  • GET /accounts              │   │                                 │
│  • GET /entitlements          │   │  ~200 lines of Python           │
│  • POST /rpc/check_entitlement│   │                                 │
│  • POST /rpc/meter_consumption│   │                                 │
│                               │   │                                 │
│  ~0 lines of code             │   │                                 │
└───────────────────────────────┘   └─────────────────────────────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      PostgreSQL :5432                                │
│                                                                      │
│   LAYER 0: Foundation                                               │
│   • account_types, accounts, units, resource_types                  │
│   • limit_kinds, window_types, limit_actions                        │
│                                                                      │
│   LAYER 0.5: Plans                                                  │
│   • plans, plan_entitlement_templates                               │
│                                                                      │
│   LAYER 1: Metering                                                 │
│   • consumption_ledger (append-only)                                │
│   • consumption_event_details                                       │
│                                                                      │
│   LAYER 2: Entitlements                                             │
│   • entitlements, entitlement_conditions, entitlements_audit        │
│                                                                      │
│   LAYER 3: Controls                                                 │
│   • control_rules, concurrency_leases, control_decisions_log        │
│                                                                      │
│   FUNCTIONS: fn_check_entitlement, fn_meter_consumption,            │
│              fn_acquire_lease, fn_release_lease, etc.               │
│                                                                      │
│   SECURITY: Row-Level Security (RLS) policies                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │       Redis :6379             │
                    │   (Caching - Optional)        │
                    └───────────────────────────────┘
```

### Request Flow: Control Check

```
1. Client: POST /api/rpc/check_entitlement
   Body: { "p_account_id": "uuid", "p_resource_type": "benchmark_runs", "p_requested_qty": 1 }

2. nginx: Route to PostgREST (matches /api/*)

3. PostgREST: 
   - Verify JWT
   - Set role from JWT claims
   - Call: SELECT * FROM api.check_entitlement(...)

4. PostgreSQL:
   - fn_check_entitlement() executes
   - Finds applicable entitlement
   - Calculates current usage
   - Applies control rules
   - Returns decision

5. Response: { "decision": "allow", "quantity_remaining": 55, ... }

Total time: ~10-30ms
```

---

## Project Structure

```
mec-service/
│
├── database/                      # PostgreSQL
│   ├── schema.sql                 # Tables, views, functions, triggers
│   ├── seed.sql                   # Lookup data, sample plans
│   ├── security.sql               # Roles, RLS, API schema
│   └── README.md                  # Database documentation
│
├── postgrest/                     # PostgREST (auto-REST)
│   ├── postgrest.conf             # Configuration
│   └── Dockerfile
│
├── nginx/                         # API Gateway
│   ├── nginx.conf                 # Routing, rate limits
│   └── Dockerfile
│
├── api/                           # FastAPI (webhooks only)
│   ├── main.py                    # App entry point
│   ├── requirements.txt           # Python dependencies
│   ├── Dockerfile
│   └── app/
│       ├── config.py              # Settings from env
│       └── routers/
│           ├── webhooks.py        # Stripe, Auth0 handlers
│           ├── admin.py           # Bulk operations
│           └── health.py          # Health checks
│
├── docker/
│   └── docker-compose.yml         # All services
│
├── docs/
│   ├── IMPLEMENTATION_PLAN.md     # This file
│   ├── LICENSING_MODELS_GUIDE.md  # Pricing scenarios
│   └── POSTGREST_PROPOSAL.md      # Architecture decision
│
├── tests/                         # (To be created)
│   ├── test_api.py
│   ├── test_webhooks.py
│   └── test_database.py
│
├── .env.example                   # Environment template
├── .gitignore
└── README.md
```

---

## Implementation Status

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1: Foundation** | ✅ COMPLETE | Database schema, seed data, security |
| **Phase 2: API Layer** | ✅ COMPLETE | PostgREST, nginx, FastAPI skeleton |
| **Phase 3: Integration** | 🔄 IN PROGRESS | Webhook implementations, external APIs |
| **Phase 4: Testing** | ⏳ PENDING | Unit, integration, load tests |
| **Phase 5: Production** | ⏳ PENDING | Monitoring, deployment, hardening |

---

## Phase 1: Foundation (COMPLETE)

### 1.1 Database Schema ✅

**File**: `database/schema.sql`

| Layer | Tables | Purpose |
|-------|--------|---------|
| 0 | account_types, accounts, units, resource_types, limit_kinds, window_types, limit_actions | Foundation/lookup |
| 0.5 | plans, plan_entitlement_templates | Commercial packages |
| 1 | consumption_ledger, consumption_event_details | Usage tracking |
| 2 | entitlements, entitlement_conditions, entitlements_audit | Quotas/limits |
| 3 | control_rules, concurrency_leases, control_decisions_log | Access control |

**Functions created**:
- `fn_check_entitlement()` - Main control check
- `fn_meter_consumption()` - Record usage
- `fn_acquire_lease()` - Get concurrency slot
- `fn_release_lease()` - Release slot
- `fn_heartbeat_lease()` - Extend lease
- `fn_provision_plan_entitlements()` - Assign plan
- `fn_get_usage()` - Calculate usage
- `fn_get_window_boundaries()` - Window calculation

**Triggers created**:
- Auto-update `updated_at` timestamps
- Prevent ledger modifications (append-only)
- Validate units against resource types
- Validate account hierarchy
- Audit entitlement changes

### 1.2 Seed Data ✅

**File**: `database/seed.sql`

- Account types: user, organization, team
- Units: count, days, hours, minutes, tokens, gpu_hours, bytes, requests
- Limit kinds: cumulative, concurrency, inventory, time_access
- Window types: calendar_month, billing_cycle, rolling_30d, rolling_7d, none
- Limit actions: block, warn, grace, overage
- Resource types: benchmark_runs, gpu_hours, concurrent_users, etc.
- Sample plans: trial-14d, starter, pro, enterprise

### 1.3 Security ✅

**File**: `database/security.sql`

**Roles**:
- `authenticator` - PostgREST connection role
- `mec_anon` - Unauthenticated requests
- `mec_user` - Authenticated users
- `mec_service` - Internal services
- `mec_admin` - Administrative access

**API Schema**:
- Views with namespace filtering
- Wrapper functions for RPC calls
- Grants per role

**Row-Level Security**:
- All tables filtered by `namespace_id` from JWT
- Service/admin roles bypass RLS

---

## Phase 2: API Layer (COMPLETE)

### 2.1 PostgREST ✅

**File**: `postgrest/postgrest.conf`

Configuration:
- Connects as `authenticator` role
- Exposes `api` schema
- JWT validation with role switching
- 1000 max rows per request

### 2.2 nginx Gateway ✅

**File**: `nginx/nginx.conf`

Routing:
- `/api/*` → PostgREST
- `/webhooks/*` → FastAPI
- `/admin/*` → FastAPI
- `/health` → Direct response

Features:
- Rate limiting (100 req/s API, 10 req/s webhooks)
- Security headers
- Gzip compression

### 2.3 FastAPI ✅

**File**: `api/main.py` and `api/app/routers/`

Endpoints:
- `POST /webhooks/stripe` - Subscription events
- `POST /webhooks/auth0` - User sync
- `POST /admin/bulk-provision` - Batch operations
- `GET /health` - Health check

---

## Phase 3: Integration (IN PROGRESS)

### 3.1 Stripe Webhook Implementation

**Status**: Skeleton created, needs completion

**File**: `api/app/routers/webhooks.py`

```python
# TODO: Complete these handlers

async def handle_subscription_created(subscription: dict):
    """
    When Stripe subscription created:
    1. Find/create account by customer_id (external_id)
    2. Map price_id to plan_id
    3. Call PostgREST: POST /rpc/provision_plan
    """
    pass

async def handle_subscription_deleted(subscription: dict):
    """
    When Stripe subscription cancelled:
    1. Find account by customer_id
    2. Update entitlements to status='expired'
    """
    pass
```

**Tasks**:
- [ ] Map Stripe price IDs to MEC plan IDs
- [ ] Implement account lookup/creation
- [ ] Call PostgREST to provision entitlements
- [ ] Handle subscription updates (plan changes)
- [ ] Handle payment failures

### 3.2 Auth0 Integration

**Status**: Skeleton created, needs completion

**Tasks**:
- [ ] Verify Auth0 webhook signatures
- [ ] Create MEC account on user signup
- [ ] Sync user profile changes
- [ ] Handle user deletion

### 3.3 Insights API Integration

**Status**: Not started

**Tasks**:
- [ ] Document how Insights API should call MEC
- [ ] Create JWT generation for service-to-service auth
- [ ] Implement control checks before benchmark runs
- [ ] Record consumption after runs complete

---

## Phase 4: Testing

### 4.1 Database Tests

```bash
# Test functions directly
docker exec -it mec-db psql -U mec -d mec -c "
  SELECT * FROM fn_check_entitlement(
    'account-uuid'::UUID,
    'benchmark_runs',
    NULL,
    1
  );
"
```

**Test cases**:
- [ ] Control check: allow when under limit
- [ ] Control check: deny when over limit
- [ ] Control check: warn at threshold
- [ ] Metering: idempotency (duplicate key ignored)
- [ ] Leases: acquire, heartbeat, release, expire
- [ ] Plan provisioning: creates all entitlements

### 4.2 API Tests

```bash
# Test via curl
curl -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{"p_account_id": "uuid", "p_resource_type": "benchmark_runs"}'
```

**Test cases**:
- [ ] All RPC endpoints return expected results
- [ ] JWT validation works
- [ ] RLS filters data correctly
- [ ] Rate limiting triggers at threshold

### 4.3 Webhook Tests

**Test cases**:
- [ ] Stripe signature validation
- [ ] Subscription created → entitlements provisioned
- [ ] Subscription deleted → entitlements expired
- [ ] Auth0 user created → account created

### 4.4 Load Tests

**Tools**: Locust or k6

**Targets**:
- Control checks: < 50ms p99 at 1000 req/s
- Metering: < 100ms p99 at 500 req/s

---

## Phase 5: Production Hardening

### 5.1 Monitoring

**Tasks**:
- [ ] Add Prometheus metrics endpoint
- [ ] Create Grafana dashboards
- [ ] Set up alerts for:
  - High latency
  - Error rates
  - Database connections
  - Lease expiration backlog

### 5.2 Logging

**Tasks**:
- [ ] Structured JSON logging
- [ ] Request tracing (correlation IDs)
- [ ] Audit log for compliance

### 5.3 Security

**Tasks**:
- [ ] Generate strong JWT secret
- [ ] Set up SSL certificates
- [ ] Configure CORS for production domains
- [ ] Rotate database passwords
- [ ] Enable pg_audit for database logging

### 5.4 Deployment

**Options**:
1. **Docker Compose** (simple)
2. **Kubernetes** (scalable)
3. **AWS ECS/Fargate** (managed)

**Tasks**:
- [ ] Create production docker-compose or k8s manifests
- [ ] Set up CI/CD pipeline
- [ ] Configure auto-scaling
- [ ] Set up database backups

---

## API Reference

### PostgREST Endpoints

#### Check Entitlement
```http
POST /api/rpc/check_entitlement
Content-Type: application/json
Authorization: Bearer <jwt>

{
  "p_account_id": "uuid",
  "p_resource_type": "benchmark_runs",
  "p_resource_scope": null,
  "p_requested_qty": 1
}
```

Response:
```json
{
  "decision": "allow",
  "reason": "Within entitlement",
  "entitlement_id": "uuid",
  "quantity_allowed": 100,
  "quantity_used": 45,
  "quantity_remaining": 55,
  "percent_used": 45.0,
  "limit_kind": "cumulative"
}
```

#### Record Consumption
```http
POST /api/rpc/meter_consumption
Content-Type: application/json
Authorization: Bearer <jwt>

{
  "p_idempotency_key": "run_12345_benchmark",
  "p_account_id": "uuid",
  "p_resource_type": "benchmark_runs",
  "p_quantity": 1,
  "p_unit_code": "count"
}
```

Response: `"event-uuid"`

#### Acquire Lease
```http
POST /api/rpc/acquire_lease
Content-Type: application/json
Authorization: Bearer <jwt>

{
  "p_account_id": "uuid",
  "p_resource_type": "concurrent_users",
  "p_session_token": "session_abc123",
  "p_ttl_minutes": 60
}
```

Response:
```json
{
  "success": true,
  "lease_id": "uuid",
  "decision": "allow",
  "reason": "Within entitlement",
  "expires_at": "2026-01-30T12:00:00Z"
}
```

#### List Resources (CRUD)
```http
GET /api/accounts
GET /api/entitlements?account_id=eq.uuid
GET /api/consumption?account_id=eq.uuid&occurred_at=gte.2026-01-01
GET /api/plans?status=eq.active
```

### FastAPI Endpoints

#### Stripe Webhook
```http
POST /webhooks/stripe
Stripe-Signature: <signature>

{ Stripe event payload }
```

#### Admin: Bulk Provision
```http
POST /admin/bulk-provision
Authorization: Bearer <jwt>

{
  "account_ids": ["uuid1", "uuid2"],
  "plan_id": "pro"
}
```

---

## Deployment Guide

### Local Development

```bash
# 1. Clone repository
git clone https://github.com/sharveshram-metrum-ai/MEC.git
cd MEC

# 2. Configure environment
cp .env.example .env
# Edit .env with your settings

# 3. Start services
cd docker
docker-compose up -d

# 4. Verify
curl http://localhost:8000/health
curl http://localhost:8000/api/plans
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | Database password | mec_dev_password |
| `JWT_SECRET` | JWT signing key (min 32 chars) | - |
| `AUTHENTICATOR_PASSWORD` | PostgREST db role password | - |
| `STRIPE_API_KEY` | Stripe secret key | - |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret | - |
| `AUTH0_DOMAIN` | Auth0 tenant domain | - |

### JWT Format

```json
{
  "sub": "user-id",
  "role": "mec_user",
  "namespace_id": "metrum-insights",
  "aud": "mec-service",
  "exp": 1735689600
}
```

---

## Next Steps

1. **Complete webhook handlers** - Stripe subscription → entitlement provisioning
2. **Integration with Insights API** - Control checks before benchmark runs
3. **Testing** - Unit tests, integration tests, load tests
4. **Production setup** - Secrets, SSL, monitoring

---

*Document Version: 2.0 (Hybrid Architecture)*  
*Last Updated: January 2026*  
*Repository: https://github.com/sharveshram-metrum-ai/MEC*
