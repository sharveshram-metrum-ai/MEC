# MEC - Metering, Entitlements, Controls

A production-ready microservice for consumption tracking, entitlement management, and access control.

## Architecture: Hybrid (PostgREST + FastAPI)

```
┌─────────────────────────────────────────────────────────────┐
│                    nginx (API Gateway)                       │
│              Routing, Rate Limiting, Caching                 │
└─────────────────────────────────────────────────────────────┘
                │                           │
                ▼                           ▼
┌───────────────────────────┐   ┌─────────────────────────────┐
│       PostgREST           │   │        FastAPI              │
│   (90% of traffic)        │   │    (Webhooks & Admin)       │
│                           │   │                             │
│   /api/accounts           │   │   /webhooks/stripe          │
│   /api/entitlements       │   │   /webhooks/auth0           │
│   /api/rpc/check_entitlement│   │   /admin/bulk-provision     │
│   /api/rpc/meter_consumption│   │   /admin/sync-usage         │
└───────────────────────────┘   └─────────────────────────────┘
                │                           │
                └───────────┬───────────────┘
                            ▼
                ┌─────────────────────┐
                │     PostgreSQL      │
                │   (Business Logic)  │
                └─────────────────────┘
```

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your settings

# 2. Start all services
cd docker
docker-compose up -d

# 3. Wait for initialization (~30 seconds)
docker-compose logs -f db

# 4. Test the API
curl http://localhost:8000/health
curl http://localhost:8000/api/plans
```

## API Endpoints

### Main API (PostgREST) - `/api/`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/accounts` | GET | List accounts |
| `/api/entitlements` | GET | List entitlements |
| `/api/active_entitlements` | GET | Currently active entitlements |
| `/api/consumption` | GET | Usage history |
| `/api/plans` | GET | Available plans |
| `/api/rpc/check_entitlement` | POST | Check if action allowed |
| `/api/rpc/meter_consumption` | POST | Record usage |
| `/api/rpc/acquire_lease` | POST | Get concurrency slot |
| `/api/rpc/release_lease` | POST | Release slot |
| `/api/rpc/provision_plan` | POST | Assign plan to account |

### Webhooks (FastAPI) - `/webhooks/`

| Endpoint | Description |
|----------|-------------|
| `/webhooks/stripe` | Stripe subscription events |
| `/webhooks/auth0` | Auth0 user events |

### Admin (FastAPI) - `/admin/`

| Endpoint | Description |
|----------|-------------|
| `/admin/bulk-provision` | Provision multiple accounts |
| `/admin/sync-usage-to-stripe` | Report usage to billing |
| `/admin/expire-stale-leases` | Cleanup job |

## Example Usage

### Check Entitlement

```bash
curl -X POST http://localhost:8000/api/rpc/check_entitlement \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{
    "p_account_id": "uuid-here",
    "p_resource_type": "benchmark_runs",
    "p_requested_qty": 1
  }'
```

Response:
```json
{
  "decision": "allow",
  "reason": "Within entitlement",
  "quantity_allowed": 100,
  "quantity_used": 45,
  "quantity_remaining": 55,
  "percent_used": 45.0
}
```

### Record Consumption

```bash
curl -X POST http://localhost:8000/api/rpc/meter_consumption \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d '{
    "p_idempotency_key": "run_12345",
    "p_account_id": "uuid-here",
    "p_resource_type": "benchmark_runs",
    "p_quantity": 1
  }'
```

## Project Structure

```
mec-service/
├── api/                    # FastAPI (webhooks & admin)
│   ├── app/
│   │   ├── routers/
│   │   │   ├── webhooks.py
│   │   │   ├── admin.py
│   │   │   └── health.py
│   │   └── config.py
│   ├── main.py
│   └── Dockerfile
├── database/
│   ├── schema.sql          # Tables, views, functions
│   ├── seed.sql            # Lookup data, sample plans
│   └── security.sql        # Roles, RLS policies
├── docker/
│   └── docker-compose.yml  # All services
├── nginx/
│   ├── nginx.conf          # API gateway routing
│   └── Dockerfile
├── postgrest/
│   ├── postgrest.conf      # PostgREST config
│   └── Dockerfile
├── docs/
│   ├── LICENSING_MODELS_GUIDE.md
│   └── POSTGREST_PROPOSAL.md
└── .env.example
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| nginx | 8000 | API Gateway |
| postgrest | 3000 | REST API (internal) |
| fastapi | 8005 | Webhooks (internal) |
| postgres | 5432 | Database |
| redis | 6379 | Caching |

## Development

```bash
# Start services
cd docker && docker-compose up -d

# View logs
docker-compose logs -f

# Reset database
docker-compose down -v
docker-compose up -d

# Direct database access
docker exec -it mec-db psql -U mec -d mec
```

## Authentication

PostgREST uses JWT for authentication. Include token in header:

```
Authorization: Bearer <jwt_token>
```

JWT must contain:
- `role`: One of `mec_user`, `mec_service`, `mec_admin`
- `namespace_id`: Tenant identifier (for RLS)

## Documentation

| Document | Description |
|----------|-------------|
| [LICENSING_MODELS_GUIDE.md](docs/LICENSING_MODELS_GUIDE.md) | Pricing scenarios with SQL |
| [POSTGREST_PROPOSAL.md](docs/POSTGREST_PROPOSAL.md) | Architecture decision |
| [database/README.md](database/README.md) | Schema documentation |

## License

Proprietary - Metrum AI
