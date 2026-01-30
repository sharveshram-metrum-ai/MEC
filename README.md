# MEC - Metering, Entitlements, Controls

A production-ready microservice for consumption tracking, entitlement management, and access control.

## Overview

MEC provides three core capabilities:

| Layer | Component | Purpose |
|-------|-----------|---------|
| **Layer 1** | Metering | Append-only consumption ledger |
| **Layer 2** | Entitlements | Quotas, limits, and plans |
| **Layer 3** | Controls | Real-time allow/deny decisions |

## Features

- **Usage Tracking** - Record consumption with idempotency
- **Flexible Licensing** - Time-based, usage-based, seat-based, inventory limits
- **Commercial Plans** - Starter, Pro, Enterprise tiers
- **Concurrency Control** - Floating/named user seats
- **Overage Billing** - Allow usage beyond limits with billing flags
- **Audit Trail** - Full history for compliance

## Quick Start

### 1. Start Database

```bash
cd docker
docker-compose up -d
```

This starts PostgreSQL with the schema and seed data automatically loaded.

### 2. Verify Setup

```bash
# Connect to database
docker exec -it mec-db psql -U mec -d mec

# Check tables exist
\dt

# Test a function
SELECT * FROM fn_check_entitlement(
    uuid_generate_v4(), 
    'benchmark_runs'
);
```

## Project Structure

```
mec-service/
├── database/
│   ├── schema.sql       # Full DDL (tables, functions, triggers)
│   └── seed.sql         # Lookup data and sample plans
├── docker/
│   └── docker-compose.yml
├── docs/
│   ├── LICENSING_MODELS_GUIDE.md
│   └── POSTGREST_PROPOSAL.md
├── .env.example
└── README.md
```

## API Layer (Pending Decision)

Architecture decision pending between:
- **Option A**: Pure FastAPI
- **Option B**: Hybrid (PostgREST + FastAPI)

See `docs/POSTGREST_PROPOSAL.md` for details.

## Database Functions

| Function | Description |
|----------|-------------|
| `fn_check_entitlement()` | Check if action is allowed |
| `fn_acquire_lease()` | Acquire concurrency lease |
| `fn_release_lease()` | Release a lease |
| `fn_heartbeat_lease()` | Extend lease expiry |
| `fn_meter_consumption()` | Record usage event |
| `fn_provision_plan_entitlements()` | Create entitlements from plan |

## Supported Licensing Models

- **Time-based**: Trials, subscriptions, annual licenses
- **Usage-based**: Pay-as-you-go, tiered pricing, overage
- **Seat-based**: Named users, floating/concurrent users
- **Inventory**: Server configs, AI models, etc.
- **Hybrid**: Combine any of the above

See `docs/LICENSING_MODELS_GUIDE.md` for examples.

## Configuration

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
# Edit .env with your values
```

Key settings:
- `DATABASE_URL` - PostgreSQL connection
- `JWT_SECRET` - For authentication
- `REDIS_URL` - For caching (optional)

## Development

```bash
# Start services
cd docker && docker-compose up -d

# View logs
docker-compose logs -f db

# Reset database
docker-compose down -v
docker-compose up -d
```

## Documentation

| Document | Description |
|----------|-------------|
| [LICENSING_MODELS_GUIDE.md](docs/LICENSING_MODELS_GUIDE.md) | All pricing scenarios with SQL examples |
| [POSTGREST_PROPOSAL.md](docs/POSTGREST_PROPOSAL.md) | API architecture decision |

## License

Proprietary - Metrum AI
