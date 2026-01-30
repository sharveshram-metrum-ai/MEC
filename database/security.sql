-- ============================================================================
-- MEC SECURITY - PostgreSQL Roles and Row-Level Security
-- Run after schema.sql and seed.sql
-- ============================================================================

-- ============================================================================
-- ROLES
-- ============================================================================

-- Authenticator role (used by PostgREST to connect)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'change_me_in_production';
    END IF;
END
$$;

-- Anonymous role (unauthenticated requests)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mec_anon') THEN
        CREATE ROLE mec_anon NOLOGIN;
    END IF;
END
$$;

-- Authenticated user role (JWT-authenticated requests)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mec_user') THEN
        CREATE ROLE mec_user NOLOGIN;
    END IF;
END
$$;

-- Service role (internal services, full access)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mec_service') THEN
        CREATE ROLE mec_service NOLOGIN;
    END IF;
END
$$;

-- Admin role (administrative operations)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mec_admin') THEN
        CREATE ROLE mec_admin NOLOGIN;
    END IF;
END
$$;

-- Grant role switching to authenticator
GRANT mec_anon TO authenticator;
GRANT mec_user TO authenticator;
GRANT mec_service TO authenticator;
GRANT mec_admin TO authenticator;

-- ============================================================================
-- SCHEMA FOR API
-- ============================================================================

-- Create API schema (PostgREST will expose this)
CREATE SCHEMA IF NOT EXISTS api;

-- ============================================================================
-- API VIEWS (Exposed via PostgREST)
-- ============================================================================

-- Accounts (filtered by namespace from JWT)
CREATE OR REPLACE VIEW api.accounts AS
SELECT 
    account_id,
    namespace_id,
    account_type_code,
    parent_account_id,
    external_id,
    display_name,
    email,
    status,
    created_at,
    updated_at
FROM public.accounts
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Entitlements (filtered by namespace)
CREATE OR REPLACE VIEW api.entitlements AS
SELECT 
    e.entitlement_id,
    e.namespace_id,
    e.account_id,
    e.resource_type_code,
    e.resource_scope,
    e.limit_kind_code,
    e.quantity_allowed,
    e.unit_code,
    e.effective_start,
    e.effective_end,
    e.window_type_code,
    e.plan_id,
    e.priority,
    e.status,
    e.created_at,
    e.updated_at
FROM public.entitlements e
WHERE e.namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Active entitlements view
CREATE OR REPLACE VIEW api.active_entitlements AS
SELECT * FROM public.v_active_entitlements
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Consumption ledger (read-only view)
CREATE OR REPLACE VIEW api.consumption AS
SELECT 
    event_id,
    idempotency_key,
    namespace_id,
    account_id,
    resource_type_code,
    resource_scope,
    quantity,
    unit_code,
    occurred_at,
    period_start,
    period_end,
    is_correction,
    created_at
FROM public.consumption_ledger
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Active leases
CREATE OR REPLACE VIEW api.active_leases AS
SELECT * FROM public.v_active_leases
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Plans (public, read-only)
CREATE OR REPLACE VIEW api.plans AS
SELECT 
    plan_id,
    namespace_id,
    plan_name,
    description,
    is_trial,
    trial_days,
    status,
    created_at
FROM public.plans
WHERE status = 'active'
  AND namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Resource types (lookup)
CREATE OR REPLACE VIEW api.resource_types AS
SELECT * FROM public.resource_types
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- Control decisions log
CREATE OR REPLACE VIEW api.control_decisions AS
SELECT * FROM public.control_decisions_log
WHERE namespace_id = COALESCE(
    current_setting('request.jwt.claims', true)::json->>'namespace_id',
    'default'
);

-- ============================================================================
-- API FUNCTIONS (Exposed via PostgREST /rpc/)
-- ============================================================================

-- Check entitlement (main control check)
CREATE OR REPLACE FUNCTION api.check_entitlement(
    p_account_id UUID,
    p_resource_type VARCHAR(64),
    p_resource_scope VARCHAR(128) DEFAULT NULL,
    p_requested_qty NUMERIC(18,6) DEFAULT 1
)
RETURNS TABLE (
    decision VARCHAR(16),
    reason VARCHAR(255),
    entitlement_id UUID,
    quantity_allowed NUMERIC(18,6),
    quantity_used NUMERIC(18,6),
    quantity_remaining NUMERIC(18,6),
    percent_used NUMERIC(7,4),
    limit_kind VARCHAR(32)
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.decision,
        r.reason,
        r.entitlement_id,
        r.quantity_allowed,
        r.quantity_used,
        r.quantity_remaining,
        r.percent_used,
        r.limit_kind
    FROM public.fn_check_entitlement(
        p_account_id, 
        p_resource_type, 
        p_resource_scope, 
        p_requested_qty
    ) r;
END;
$$;

-- Record consumption
CREATE OR REPLACE FUNCTION api.meter_consumption(
    p_idempotency_key VARCHAR(255),
    p_account_id UUID,
    p_resource_type VARCHAR(64),
    p_quantity NUMERIC(18,6),
    p_unit_code VARCHAR(32) DEFAULT NULL,
    p_resource_scope VARCHAR(128) DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN public.fn_meter_consumption(
        p_idempotency_key,
        p_account_id,
        p_resource_type,
        p_quantity,
        p_unit_code,
        p_resource_scope
    );
END;
$$;

-- Acquire lease
CREATE OR REPLACE FUNCTION api.acquire_lease(
    p_account_id UUID,
    p_resource_type VARCHAR(64),
    p_resource_scope VARCHAR(128) DEFAULT NULL,
    p_session_token VARCHAR(255) DEFAULT NULL,
    p_ttl_minutes INT DEFAULT 60
)
RETURNS TABLE (
    success BOOLEAN,
    lease_id UUID,
    decision VARCHAR(16),
    reason VARCHAR(255),
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.fn_acquire_lease(
        p_account_id,
        p_resource_type,
        p_resource_scope,
        p_session_token,
        p_ttl_minutes
    );
END;
$$;

-- Release lease
CREATE OR REPLACE FUNCTION api.release_lease(p_lease_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN public.fn_release_lease(p_lease_id);
END;
$$;

-- Heartbeat lease
CREATE OR REPLACE FUNCTION api.heartbeat_lease(
    p_lease_id UUID,
    p_extend_minutes INT DEFAULT 60
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN public.fn_heartbeat_lease(p_lease_id, p_extend_minutes);
END;
$$;

-- Provision plan entitlements
CREATE OR REPLACE FUNCTION api.provision_plan(
    p_account_id UUID,
    p_plan_id VARCHAR(64),
    p_start_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN public.fn_provision_plan_entitlements(p_account_id, p_plan_id, p_start_date);
END;
$$;

-- Get usage summary
CREATE OR REPLACE FUNCTION api.get_usage(
    p_account_id UUID,
    p_resource_type VARCHAR(64),
    p_resource_scope VARCHAR(128) DEFAULT NULL,
    p_window_start TIMESTAMPTZ DEFAULT NULL,
    p_window_end TIMESTAMPTZ DEFAULT NULL
)
RETURNS NUMERIC(18,6)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN public.fn_get_usage(
        p_account_id,
        p_resource_type,
        p_resource_scope,
        p_window_start,
        p_window_end
    );
END;
$$;

-- ============================================================================
-- GRANTS - Anonymous (very limited)
-- ============================================================================

GRANT USAGE ON SCHEMA api TO mec_anon;
GRANT SELECT ON api.plans TO mec_anon;
GRANT SELECT ON api.resource_types TO mec_anon;

-- ============================================================================
-- GRANTS - Authenticated Users
-- ============================================================================

GRANT USAGE ON SCHEMA api TO mec_user;

-- Read access
GRANT SELECT ON api.accounts TO mec_user;
GRANT SELECT ON api.entitlements TO mec_user;
GRANT SELECT ON api.active_entitlements TO mec_user;
GRANT SELECT ON api.consumption TO mec_user;
GRANT SELECT ON api.active_leases TO mec_user;
GRANT SELECT ON api.plans TO mec_user;
GRANT SELECT ON api.resource_types TO mec_user;
GRANT SELECT ON api.control_decisions TO mec_user;

-- Function access
GRANT EXECUTE ON FUNCTION api.check_entitlement TO mec_user;
GRANT EXECUTE ON FUNCTION api.meter_consumption TO mec_user;
GRANT EXECUTE ON FUNCTION api.acquire_lease TO mec_user;
GRANT EXECUTE ON FUNCTION api.release_lease TO mec_user;
GRANT EXECUTE ON FUNCTION api.heartbeat_lease TO mec_user;
GRANT EXECUTE ON FUNCTION api.get_usage TO mec_user;

-- ============================================================================
-- GRANTS - Service Role (internal services)
-- ============================================================================

GRANT USAGE ON SCHEMA api TO mec_service;
GRANT USAGE ON SCHEMA public TO mec_service;

-- Full access to API
GRANT ALL ON ALL TABLES IN SCHEMA api TO mec_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO mec_service;

-- Direct access to public schema for internal operations
GRANT SELECT, INSERT ON public.consumption_ledger TO mec_service;
GRANT SELECT, INSERT, UPDATE ON public.entitlements TO mec_service;
GRANT SELECT, INSERT, UPDATE ON public.accounts TO mec_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.concurrency_leases TO mec_service;
GRANT SELECT ON public.plans TO mec_service;
GRANT SELECT ON public.plan_entitlement_templates TO mec_service;
GRANT SELECT ON public.resource_types TO mec_service;
GRANT SELECT ON public.units TO mec_service;
GRANT INSERT ON public.control_decisions_log TO mec_service;
GRANT INSERT ON public.entitlements_audit TO mec_service;

-- Provision plans
GRANT EXECUTE ON FUNCTION api.provision_plan TO mec_service;

-- ============================================================================
-- GRANTS - Admin Role
-- ============================================================================

GRANT USAGE ON SCHEMA api TO mec_admin;
GRANT USAGE ON SCHEMA public TO mec_admin;

-- Full access
GRANT ALL ON ALL TABLES IN SCHEMA api TO mec_admin;
GRANT ALL ON ALL TABLES IN SCHEMA public TO mec_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO mec_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO mec_admin;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on key tables
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consumption_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.concurrency_leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_decisions_log ENABLE ROW LEVEL SECURITY;

-- Accounts: Users can only see accounts in their namespace
CREATE POLICY accounts_namespace_isolation ON public.accounts
    FOR ALL
    USING (
        namespace_id = COALESCE(
            current_setting('request.jwt.claims', true)::json->>'namespace_id',
            'default'
        )
        OR current_user IN ('mec_service', 'mec_admin', 'mec')
    );

-- Entitlements: Namespace isolation
CREATE POLICY entitlements_namespace_isolation ON public.entitlements
    FOR ALL
    USING (
        namespace_id = COALESCE(
            current_setting('request.jwt.claims', true)::json->>'namespace_id',
            'default'
        )
        OR current_user IN ('mec_service', 'mec_admin', 'mec')
    );

-- Consumption: Namespace isolation
CREATE POLICY consumption_namespace_isolation ON public.consumption_ledger
    FOR ALL
    USING (
        namespace_id = COALESCE(
            current_setting('request.jwt.claims', true)::json->>'namespace_id',
            'default'
        )
        OR current_user IN ('mec_service', 'mec_admin', 'mec')
    );

-- Leases: Namespace isolation
CREATE POLICY leases_namespace_isolation ON public.concurrency_leases
    FOR ALL
    USING (
        namespace_id = COALESCE(
            current_setting('request.jwt.claims', true)::json->>'namespace_id',
            'default'
        )
        OR current_user IN ('mec_service', 'mec_admin', 'mec')
    );

-- Decisions: Namespace isolation
CREATE POLICY decisions_namespace_isolation ON public.control_decisions_log
    FOR ALL
    USING (
        namespace_id = COALESCE(
            current_setting('request.jwt.claims', true)::json->>'namespace_id',
            'default'
        )
        OR current_user IN ('mec_service', 'mec_admin', 'mec')
    );

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Uncomment to verify setup:
-- SELECT rolname FROM pg_roles WHERE rolname LIKE 'mec%' OR rolname = 'authenticator';
-- SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'api';
-- SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'api';
