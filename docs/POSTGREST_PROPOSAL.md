# Proposal: PostgREST for MEC Service

**Date:** January 2026  
**Author:** Development Team  
**Status:** For Discussion

---

## The Idea

Use **PostgREST** instead of (or alongside) FastAPI for the MEC service.

**PostgREST** is a standalone server that automatically turns a PostgreSQL database into a REST API — no code needed.

---

## Why This Makes Sense for MEC

MEC is uniquely suited for PostgREST because:

| Factor | Our Situation |
|--------|---------------|
| Business logic location | Already in PostgreSQL functions (`fn_check_entitlement`, etc.) |
| Data model | Well-designed with views, triggers, constraints |
| Primary operations | Database reads/writes + function calls |
| Performance requirements | < 50ms response time needed |

With PostgREST, our existing database functions become API endpoints automatically:

```
PostgreSQL Function              →    REST Endpoint
─────────────────────────────────────────────────────
fn_check_entitlement()           →    POST /rpc/fn_check_entitlement
fn_acquire_lease()               →    POST /rpc/fn_acquire_lease
fn_meter_consumption()           →    POST /rpc/fn_meter_consumption
fn_provision_plan_entitlements() →    POST /rpc/fn_provision_plan_entitlements
```

---

## Three Options

### Option A: Pure FastAPI (Current Plan)

```
Client → FastAPI (Python) → SQLAlchemy → PostgreSQL
```

| Pros | Cons |
|------|------|
| Full control | ~5,000+ lines of Python |
| Team knows Python | ORM overhead |
| Flexible | Duplicates logic already in DB |

### Option B: Pure PostgREST

```
Client → PostgREST (auto-generated) → PostgreSQL
```

| Pros | Cons |
|------|------|
| Near-zero code | Can't handle webhooks |
| Very fast | No external API calls |
| API matches schema | No caching layer |

### Option C: Hybrid (Recommended)

```
Client → nginx → PostgREST (90% of requests)
                → FastAPI (10% - webhooks only)
```

| Pros | Cons |
|------|------|
| Best performance | One more service |
| ~75% less code | Need nginx routing |
| Handles webhooks | Team needs to learn PostgREST |

---

## Code Comparison

| Component | Pure FastAPI | Hybrid |
|-----------|--------------|--------|
| SQLAlchemy models | 500 lines | 500 lines |
| Repositories | 800 lines | **0 lines** |
| Services | 1,500 lines | **200 lines** |
| API routes | 1,000 lines | **50 lines** (nginx config) |
| Tests | 2,000 lines | 500 lines |
| **Total** | **~5,800 lines** | **~1,250 lines** |

**~78% less code with hybrid approach.**

---

## Recommendation

**Hybrid approach** — for these reasons:

1. Our business logic is already in PostgreSQL functions
2. 78% less code to write and maintain
3. Better performance for core operations
4. Can still handle webhooks via FastAPI
5. Can migrate to more FastAPI later if needed

---

## Questions for Discussion

1. Is the team comfortable with PostgreSQL-first approach?
2. Do we want to add nginx as API gateway?
3. How much Python code do we want to maintain?
4. What's the priority: flexibility vs simplicity?

---

*Feedback welcome. Please share thoughts in the group.*
