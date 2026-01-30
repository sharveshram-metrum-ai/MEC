-- ============================================================================
-- MEC DATABASE DDL v3 - COMPLETE
-- General Purpose Consumption Stack (Metering, Entitlements, Controls)
-- PostgreSQL 14+
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- LAYER 0: FOUNDATION (Accounts + Lookup Tables)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: account_types
-- ----------------------------------------------------------------------------
CREATE TABLE account_types (
    account_type_code   VARCHAR(32)     PRIMARY KEY,
    description         VARCHAR(255),
    can_have_children   BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- TABLE: accounts
-- ----------------------------------------------------------------------------
CREATE TABLE accounts (
    account_id          UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    account_type_code   VARCHAR(32)     NOT NULL REFERENCES account_types(account_type_code),
    parent_account_id   UUID            REFERENCES accounts(account_id),
    external_id         VARCHAR(128),
    display_name        VARCHAR(255)    NOT NULL,
    email               VARCHAR(255),
    status              VARCHAR(16)     NOT NULL DEFAULT 'active',
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    
    CONSTRAINT uq_account_external UNIQUE (namespace_id, external_id),
    CONSTRAINT chk_no_self_parent CHECK (parent_account_id != account_id)
);

CREATE INDEX ix_account_parent ON accounts(parent_account_id);
CREATE INDEX ix_account_namespace ON accounts(namespace_id, account_type_code);
CREATE INDEX ix_account_status ON accounts(namespace_id, status);

-- ----------------------------------------------------------------------------
-- TABLE: units
-- ----------------------------------------------------------------------------
CREATE TABLE units (
    unit_code           VARCHAR(32)     PRIMARY KEY,
    unit_category       VARCHAR(32)     NOT NULL,
    description         VARCHAR(255),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- TABLE: resource_types
-- ----------------------------------------------------------------------------
CREATE TABLE resource_types (
    resource_type_code  VARCHAR(64)     PRIMARY KEY,
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    description         VARCHAR(255),
    default_unit_code   VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    is_inventory        BOOLEAN         NOT NULL DEFAULT FALSE,
    is_concurrency      BOOLEAN         NOT NULL DEFAULT FALSE,
    is_time_bound       BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_resource_type_namespace ON resource_types(namespace_id);

-- ----------------------------------------------------------------------------
-- TABLE: resource_type_allowed_units
-- ----------------------------------------------------------------------------
CREATE TABLE resource_type_allowed_units (
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    unit_code           VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    PRIMARY KEY (resource_type_code, unit_code)
);

-- ----------------------------------------------------------------------------
-- TABLE: limit_kinds
-- ----------------------------------------------------------------------------
CREATE TABLE limit_kinds (
    limit_kind_code     VARCHAR(32)     PRIMARY KEY,
    description         VARCHAR(255),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- TABLE: window_types
-- ----------------------------------------------------------------------------
CREATE TABLE window_types (
    window_type_code    VARCHAR(32)     PRIMARY KEY,
    description         VARCHAR(255),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- TABLE: limit_actions
-- ----------------------------------------------------------------------------
CREATE TABLE limit_actions (
    limit_action_code   VARCHAR(32)     PRIMARY KEY,
    description         VARCHAR(255),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- LAYER 0.5: PLANS (Commercial packaging)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: plans
-- ----------------------------------------------------------------------------
CREATE TABLE plans (
    plan_id             VARCHAR(64)     PRIMARY KEY,
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    plan_name           VARCHAR(128)    NOT NULL,
    description         TEXT,
    is_trial            BOOLEAN         NOT NULL DEFAULT FALSE,
    trial_days          INT,
    external_id         VARCHAR(128),
    status              VARCHAR(16)     NOT NULL DEFAULT 'active',
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_plan_namespace ON plans(namespace_id, status);

-- ----------------------------------------------------------------------------
-- TABLE: plan_entitlement_templates
-- ----------------------------------------------------------------------------
CREATE TABLE plan_entitlement_templates (
    template_id         UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id             VARCHAR(64)     NOT NULL REFERENCES plans(plan_id),
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    limit_kind_code     VARCHAR(32)     NOT NULL REFERENCES limit_kinds(limit_kind_code),
    quantity_allowed    NUMERIC(18,6),
    unit_code           VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    window_type_code    VARCHAR(32)     REFERENCES window_types(window_type_code),
    duration_days       INT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_plan_template ON plan_entitlement_templates(plan_id);

-- ============================================================================
-- LAYER 1: METERING (What was used)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: consumption_ledger
-- ----------------------------------------------------------------------------
CREATE TABLE consumption_ledger (
    event_id            UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    idempotency_key     VARCHAR(255)    NOT NULL UNIQUE,
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    
    account_id          UUID            NOT NULL REFERENCES accounts(account_id),
    
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    
    quantity            NUMERIC(18,6)   NOT NULL,
    unit_code           VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    
    occurred_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    period_start        TIMESTAMPTZ,
    period_end          TIMESTAMPTZ,
    
    is_correction       BOOLEAN         NOT NULL DEFAULT FALSE,
    corrects_event_id   UUID            REFERENCES consumption_ledger(event_id),
    
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_consumption_account_resource ON consumption_ledger(account_id, resource_type_code);
CREATE INDEX ix_consumption_account_resource_scope ON consumption_ledger(account_id, resource_type_code, resource_scope);
CREATE INDEX ix_consumption_occurred ON consumption_ledger(occurred_at);
CREATE INDEX ix_consumption_namespace_time ON consumption_ledger(namespace_id, occurred_at);
CREATE INDEX ix_consumption_corrections ON consumption_ledger(corrects_event_id) WHERE corrects_event_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- TABLE: consumption_event_details
-- ----------------------------------------------------------------------------
CREATE TABLE consumption_event_details (
    event_id            UUID            NOT NULL REFERENCES consumption_ledger(event_id),
    detail_key          VARCHAR(64)     NOT NULL,
    detail_value        VARCHAR(512)    NOT NULL,
    PRIMARY KEY (event_id, detail_key)
);

-- ============================================================================
-- LAYER 2: ENTITLEMENTS (What is allowed)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: entitlements
-- ----------------------------------------------------------------------------
CREATE TABLE entitlements (
    entitlement_id      UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    
    account_id          UUID            NOT NULL REFERENCES accounts(account_id),
    
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    
    limit_kind_code     VARCHAR(32)     NOT NULL REFERENCES limit_kinds(limit_kind_code),
    quantity_allowed    NUMERIC(18,6),
    unit_code           VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    
    effective_start     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    effective_end       TIMESTAMPTZ,
    
    window_type_code    VARCHAR(32)     REFERENCES window_types(window_type_code),
    window_anchor       TIMESTAMPTZ,
    
    plan_id             VARCHAR(64)     REFERENCES plans(plan_id),
    template_id         UUID            REFERENCES plan_entitlement_templates(template_id),
    
    priority            INT             NOT NULL DEFAULT 0,
    status              VARCHAR(16)     NOT NULL DEFAULT 'active',
    
    version             INT             NOT NULL DEFAULT 1,
    superseded_by       UUID            REFERENCES entitlements(entitlement_id),
    
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_entitlement_account_resource ON entitlements(account_id, resource_type_code);
CREATE INDEX ix_entitlement_account_resource_scope ON entitlements(account_id, resource_type_code, resource_scope);
CREATE INDEX ix_entitlement_status ON entitlements(status);
CREATE INDEX ix_entitlement_effective ON entitlements(effective_start, effective_end);
CREATE INDEX ix_entitlement_plan ON entitlements(plan_id);
CREATE INDEX ix_entitlement_active ON entitlements(account_id, resource_type_code, status, effective_start, effective_end) WHERE status = 'active';

-- ----------------------------------------------------------------------------
-- TABLE: entitlement_conditions
-- ----------------------------------------------------------------------------
CREATE TABLE entitlement_conditions (
    entitlement_id      UUID            NOT NULL REFERENCES entitlements(entitlement_id),
    condition_key       VARCHAR(64)     NOT NULL,
    condition_value     VARCHAR(255)    NOT NULL,
    PRIMARY KEY (entitlement_id, condition_key)
);

-- ----------------------------------------------------------------------------
-- TABLE: entitlements_audit
-- ----------------------------------------------------------------------------
CREATE TABLE entitlements_audit (
    audit_id            UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    entitlement_id      UUID            NOT NULL,
    operation           VARCHAR(16)     NOT NULL,
    old_values          JSONB,
    new_values          JSONB,
    changed_by          VARCHAR(128),
    changed_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_entitlement_audit ON entitlements_audit(entitlement_id, changed_at);

-- ============================================================================
-- LAYER 3: CONTROLS (What happens at the boundary)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: control_rules
-- ----------------------------------------------------------------------------
CREATE TABLE control_rules (
    rule_id             UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    rule_name           VARCHAR(128),
    
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    
    limit_kind_code     VARCHAR(32)     NOT NULL REFERENCES limit_kinds(limit_kind_code),
    limit_action_code   VARCHAR(32)     NOT NULL REFERENCES limit_actions(limit_action_code),
    
    warn_at_percent     NUMERIC(5,2),
    grace_quantity      NUMERIC(18,6),
    grace_window_hours  INT,
    overage_multiplier  NUMERIC(8,4),
    
    priority            INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_control_rule_resource ON control_rules(resource_type_code, resource_scope);
CREATE INDEX ix_control_rule_active ON control_rules(namespace_id, is_active) WHERE is_active = TRUE;

-- ----------------------------------------------------------------------------
-- TABLE: control_rule_conditions
-- ----------------------------------------------------------------------------
CREATE TABLE control_rule_conditions (
    rule_id             UUID            NOT NULL REFERENCES control_rules(rule_id),
    condition_key       VARCHAR(64)     NOT NULL,
    condition_value     VARCHAR(255)    NOT NULL,
    PRIMARY KEY (rule_id, condition_key)
);

-- ----------------------------------------------------------------------------
-- TABLE: concurrency_leases
-- ----------------------------------------------------------------------------
CREATE TABLE concurrency_leases (
    lease_id            UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    
    account_id          UUID            NOT NULL REFERENCES accounts(account_id),
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    
    acquired_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ     NOT NULL,
    last_heartbeat      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    released_at         TIMESTAMPTZ,
    
    session_token       VARCHAR(255),
    session_metadata    VARCHAR(512),
    
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_lease_active ON concurrency_leases(account_id, resource_type_code, released_at) WHERE released_at IS NULL;
CREATE INDEX ix_lease_expiry ON concurrency_leases(expires_at) WHERE released_at IS NULL;
CREATE INDEX ix_lease_token ON concurrency_leases(session_token) WHERE session_token IS NOT NULL;

-- ----------------------------------------------------------------------------
-- TABLE: control_decisions_log
-- ----------------------------------------------------------------------------
CREATE TABLE control_decisions_log (
    decision_id         UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id        VARCHAR(64)     NOT NULL DEFAULT 'default',
    
    account_id          UUID            NOT NULL REFERENCES accounts(account_id),
    resource_type_code  VARCHAR(64)     NOT NULL REFERENCES resource_types(resource_type_code),
    resource_scope      VARCHAR(128),
    
    requested_quantity  NUMERIC(18,6)   NOT NULL,
    unit_code           VARCHAR(32)     NOT NULL REFERENCES units(unit_code),
    
    decision            VARCHAR(16)     NOT NULL,
    reason              VARCHAR(255),
    
    rule_id             UUID            REFERENCES control_rules(rule_id),
    entitlement_id      UUID            REFERENCES entitlements(entitlement_id),
    
    usage_at_decision   NUMERIC(18,6),
    limit_at_decision   NUMERIC(18,6),
    percent_used        NUMERIC(7,4),
    
    decided_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_decision_account ON control_decisions_log(account_id, decided_at);
CREATE INDEX ix_decision_resource ON control_decisions_log(resource_type_code, decided_at);
CREATE INDEX ix_decision_outcome ON control_decisions_log(decision, decided_at);

-- ============================================================================
-- VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW v_active_entitlements AS
SELECT 
    e.*,
    a.display_name AS account_name,
    a.parent_account_id,
    p.plan_name
FROM entitlements e
JOIN accounts a ON e.account_id = a.account_id
LEFT JOIN plans p ON e.plan_id = p.plan_id
WHERE e.status = 'active'
  AND e.effective_start <= NOW()
  AND (e.effective_end IS NULL OR e.effective_end > NOW());

CREATE OR REPLACE VIEW v_active_leases AS
SELECT 
    l.*,
    a.display_name AS account_name,
    EXTRACT(EPOCH FROM (l.expires_at - NOW())) AS seconds_until_expiry
FROM concurrency_leases l
JOIN accounts a ON l.account_id = a.account_id
WHERE l.released_at IS NULL
  AND l.expires_at > NOW();

CREATE OR REPLACE VIEW v_account_hierarchy AS
SELECT 
    a.account_id,
    a.namespace_id,
    a.account_type_code,
    a.parent_account_id,
    a.display_name,
    a.status,
    COALESCE(a.parent_account_id, a.account_id) AS owner_account_id,
    pa.display_name AS owner_display_name
FROM accounts a
LEFT JOIN accounts pa ON a.parent_account_id = pa.account_id;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- fn_get_window_boundaries
CREATE OR REPLACE FUNCTION fn_get_window_boundaries(
    p_window_type_code  VARCHAR(32),
    p_window_anchor     TIMESTAMPTZ,
    p_reference_time    TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (window_start TIMESTAMPTZ, window_end TIMESTAMPTZ)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        CASE p_window_type_code
            WHEN 'calendar_month' THEN date_trunc('month', p_reference_time)
            WHEN 'billing_cycle' THEN 
                p_window_anchor + (
                    floor(
                        EXTRACT(EPOCH FROM (p_reference_time - p_window_anchor)) / 
                        (30.44 * 24 * 60 * 60)
                    )::int * INTERVAL '1 month'
                )
            WHEN 'rolling_30d' THEN p_reference_time - INTERVAL '30 days'
            WHEN 'rolling_7d' THEN p_reference_time - INTERVAL '7 days'
            WHEN 'none' THEN '-infinity'::TIMESTAMPTZ
            ELSE p_reference_time
        END AS window_start,
        CASE p_window_type_code
            WHEN 'calendar_month' THEN date_trunc('month', p_reference_time) + INTERVAL '1 month'
            WHEN 'billing_cycle' THEN 
                p_window_anchor + (
                    (floor(
                        EXTRACT(EPOCH FROM (p_reference_time - p_window_anchor)) / 
                        (30.44 * 24 * 60 * 60)
                    )::int + 1) * INTERVAL '1 month'
                )
            WHEN 'rolling_30d' THEN p_reference_time
            WHEN 'rolling_7d' THEN p_reference_time
            WHEN 'none' THEN 'infinity'::TIMESTAMPTZ
            ELSE p_reference_time + INTERVAL '1 month'
        END AS window_end;
END;
$$;

-- fn_get_owner_account_id
CREATE OR REPLACE FUNCTION fn_get_owner_account_id(p_account_id UUID)
RETURNS UUID
LANGUAGE SQL STABLE
AS $$
    SELECT COALESCE(parent_account_id, account_id)
    FROM accounts
    WHERE account_id = p_account_id;
$$;

-- fn_get_usage
CREATE OR REPLACE FUNCTION fn_get_usage(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_window_start      TIMESTAMPTZ DEFAULT NULL,
    p_window_end        TIMESTAMPTZ DEFAULT NULL,
    p_include_children  BOOLEAN DEFAULT TRUE
)
RETURNS NUMERIC(18,6)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_usage NUMERIC(18,6);
    v_owner_id UUID;
BEGIN
    v_owner_id := fn_get_owner_account_id(p_account_id);
    
    SELECT COALESCE(SUM(cl.quantity), 0)
    INTO v_usage
    FROM consumption_ledger cl
    JOIN accounts a ON cl.account_id = a.account_id
    WHERE cl.resource_type_code = p_resource_type
      AND (p_resource_scope IS NULL OR cl.resource_scope = p_resource_scope)
      AND (p_window_start IS NULL OR cl.occurred_at >= p_window_start)
      AND (p_window_end IS NULL OR cl.occurred_at < p_window_end)
      AND (
          cl.account_id = v_owner_id
          OR (p_include_children AND a.parent_account_id = v_owner_id)
      );
    
    RETURN v_usage;
END;
$$;

-- fn_get_inventory_count
CREATE OR REPLACE FUNCTION fn_get_inventory_count(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_include_children  BOOLEAN DEFAULT TRUE
)
RETURNS NUMERIC(18,6)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_count NUMERIC(18,6);
    v_owner_id UUID;
BEGIN
    v_owner_id := fn_get_owner_account_id(p_account_id);
    
    SELECT COALESCE(SUM(cl.quantity), 0)
    INTO v_count
    FROM consumption_ledger cl
    JOIN accounts a ON cl.account_id = a.account_id
    WHERE cl.resource_type_code = p_resource_type
      AND (p_resource_scope IS NULL OR cl.resource_scope = p_resource_scope)
      AND (
          cl.account_id = v_owner_id
          OR (p_include_children AND a.parent_account_id = v_owner_id)
      );
    
    RETURN v_count;
END;
$$;

-- fn_get_active_lease_count
CREATE OR REPLACE FUNCTION fn_get_active_lease_count(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_include_children  BOOLEAN DEFAULT TRUE
)
RETURNS INT
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_count INT;
    v_owner_id UUID;
BEGIN
    v_owner_id := fn_get_owner_account_id(p_account_id);
    
    SELECT COUNT(*)::INT
    INTO v_count
    FROM concurrency_leases cl
    JOIN accounts a ON cl.account_id = a.account_id
    WHERE cl.resource_type_code = p_resource_type
      AND (p_resource_scope IS NULL OR cl.resource_scope = p_resource_scope)
      AND cl.released_at IS NULL
      AND cl.expires_at > NOW()
      AND (
          cl.account_id = v_owner_id
          OR (p_include_children AND a.parent_account_id = v_owner_id)
      );
    
    RETURN v_count;
END;
$$;

-- fn_get_entitlement
CREATE OR REPLACE FUNCTION fn_get_entitlement(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_reference_time    TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
    entitlement_id      UUID,
    quantity_allowed    NUMERIC(18,6),
    unit_code           VARCHAR(32),
    limit_kind_code     VARCHAR(32),
    window_type_code    VARCHAR(32),
    window_anchor       TIMESTAMPTZ,
    effective_start     TIMESTAMPTZ,
    effective_end       TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_owner_id UUID;
BEGIN
    v_owner_id := fn_get_owner_account_id(p_account_id);
    
    RETURN QUERY
    SELECT 
        e.entitlement_id,
        e.quantity_allowed,
        e.unit_code,
        e.limit_kind_code,
        e.window_type_code,
        e.window_anchor,
        e.effective_start,
        e.effective_end
    FROM entitlements e
    WHERE e.account_id = v_owner_id
      AND e.resource_type_code = p_resource_type
      AND (p_resource_scope IS NULL OR e.resource_scope IS NULL OR e.resource_scope = p_resource_scope)
      AND e.status = 'active'
      AND e.effective_start <= p_reference_time
      AND (e.effective_end IS NULL OR e.effective_end > p_reference_time)
    ORDER BY 
        CASE WHEN e.resource_scope = p_resource_scope THEN 0 ELSE 1 END,
        e.priority DESC,
        e.created_at DESC
    LIMIT 1;
END;
$$;

-- fn_check_entitlement
CREATE OR REPLACE FUNCTION fn_check_entitlement(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_requested_qty     NUMERIC(18,6) DEFAULT 1,
    p_unit_code         VARCHAR(32) DEFAULT NULL
)
RETURNS TABLE (
    decision            VARCHAR(16),
    reason              VARCHAR(255),
    entitlement_id      UUID,
    quantity_allowed    NUMERIC(18,6),
    quantity_used       NUMERIC(18,6),
    quantity_remaining  NUMERIC(18,6),
    percent_used        NUMERIC(7,4),
    limit_kind          VARCHAR(32),
    rule_id             UUID,
    limit_action        VARCHAR(32)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_entitlement       RECORD;
    v_rule              RECORD;
    v_window            RECORD;
    v_usage             NUMERIC(18,6);
    v_remaining         NUMERIC(18,6);
    v_percent           NUMERIC(7,4);
    v_decision          VARCHAR(16);
    v_reason            VARCHAR(255);
    v_resource          RECORD;
BEGIN
    SELECT * INTO v_resource FROM resource_types WHERE resource_type_code = p_resource_type;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            'deny'::VARCHAR(16), 'Unknown resource type'::VARCHAR(255),
            NULL::UUID, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC,
            NULL::VARCHAR(32), NULL::UUID, NULL::VARCHAR(32);
        RETURN;
    END IF;
    
    SELECT * INTO v_entitlement FROM fn_get_entitlement(p_account_id, p_resource_type, p_resource_scope);
    
    IF v_entitlement IS NULL OR v_entitlement.entitlement_id IS NULL THEN
        RETURN QUERY SELECT 
            'deny'::VARCHAR(16), 'No entitlement found'::VARCHAR(255),
            NULL::UUID, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC,
            NULL::VARCHAR(32), NULL::UUID, NULL::VARCHAR(32);
        RETURN;
    END IF;
    
    IF v_entitlement.quantity_allowed IS NULL THEN
        RETURN QUERY SELECT 
            'allow'::VARCHAR(16), 'Unlimited entitlement'::VARCHAR(255),
            v_entitlement.entitlement_id, NULL::NUMERIC(18,6), 0::NUMERIC(18,6),
            NULL::NUMERIC(18,6), 0::NUMERIC(7,4), v_entitlement.limit_kind_code,
            NULL::UUID, NULL::VARCHAR(32);
        RETURN;
    END IF;
    
    IF v_entitlement.limit_kind_code = 'concurrency' THEN
        v_usage := fn_get_active_lease_count(p_account_id, p_resource_type, p_resource_scope);
    ELSIF v_entitlement.limit_kind_code = 'inventory' THEN
        v_usage := fn_get_inventory_count(p_account_id, p_resource_type, p_resource_scope);
    ELSIF v_entitlement.limit_kind_code = 'time_access' THEN
        IF NOW() BETWEEN v_entitlement.effective_start AND COALESCE(v_entitlement.effective_end, 'infinity'::TIMESTAMPTZ) THEN
            v_usage := 0;
        ELSE
            RETURN QUERY SELECT 
                'deny'::VARCHAR(16), 'Access window expired'::VARCHAR(255),
                v_entitlement.entitlement_id, v_entitlement.quantity_allowed,
                0::NUMERIC(18,6), 0::NUMERIC(18,6), 100::NUMERIC(7,4),
                v_entitlement.limit_kind_code, NULL::UUID, 'block'::VARCHAR(32);
            RETURN;
        END IF;
    ELSE
        SELECT * INTO v_window FROM fn_get_window_boundaries(v_entitlement.window_type_code, v_entitlement.window_anchor);
        v_usage := fn_get_usage(p_account_id, p_resource_type, p_resource_scope, v_window.window_start, v_window.window_end);
    END IF;
    
    v_remaining := v_entitlement.quantity_allowed - v_usage;
    v_percent := (v_usage / v_entitlement.quantity_allowed) * 100;
    
    SELECT * INTO v_rule
    FROM control_rules
    WHERE resource_type_code = p_resource_type
      AND (resource_scope IS NULL OR resource_scope = p_resource_scope)
      AND limit_kind_code = v_entitlement.limit_kind_code
      AND is_active = TRUE
    ORDER BY 
        CASE WHEN resource_scope = p_resource_scope THEN 0 ELSE 1 END,
        priority DESC
    LIMIT 1;
    
    IF v_remaining >= p_requested_qty THEN
        IF v_rule IS NOT NULL AND v_rule.warn_at_percent IS NOT NULL AND v_percent >= v_rule.warn_at_percent THEN
            v_decision := 'warn';
            v_reason := format('Usage at %.1f%% of limit', v_percent);
        ELSE
            v_decision := 'allow';
            v_reason := 'Within entitlement';
        END IF;
    ELSE
        IF v_rule IS NOT NULL THEN
            v_decision := v_rule.limit_action_code;
            IF v_rule.limit_action_code = 'grace' AND v_rule.grace_quantity IS NOT NULL THEN
                IF v_remaining + v_rule.grace_quantity >= p_requested_qty THEN
                    v_reason := 'Within grace allowance';
                ELSE
                    v_decision := 'deny';
                    v_reason := 'Grace allowance exceeded';
                END IF;
            ELSIF v_rule.limit_action_code = 'overage' THEN
                v_reason := 'Marked for overage billing';
            ELSE
                v_reason := 'Limit reached';
            END IF;
        ELSE
            v_decision := 'deny';
            v_reason := 'Limit reached, no rule defined';
        END IF;
    END IF;
    
    RETURN QUERY SELECT 
        v_decision, v_reason, v_entitlement.entitlement_id, v_entitlement.quantity_allowed,
        v_usage, v_remaining, v_percent, v_entitlement.limit_kind_code,
        v_rule.rule_id, v_rule.limit_action_code;
END;
$$;

-- fn_acquire_lease
CREATE OR REPLACE FUNCTION fn_acquire_lease(
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_session_token     VARCHAR(255) DEFAULT NULL,
    p_ttl_minutes       INT DEFAULT 60
)
RETURNS TABLE (
    success             BOOLEAN,
    lease_id            UUID,
    decision            VARCHAR(16),
    reason              VARCHAR(255),
    expires_at          TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_check             RECORD;
    v_lease_id          UUID;
    v_expires           TIMESTAMPTZ;
    v_namespace         VARCHAR(64);
BEGIN
    SELECT namespace_id INTO v_namespace FROM accounts WHERE account_id = p_account_id;
    
    SELECT * INTO v_check FROM fn_check_entitlement(p_account_id, p_resource_type, p_resource_scope, 1);
    
    IF v_check.decision NOT IN ('allow', 'warn') THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, v_check.decision, v_check.reason, NULL::TIMESTAMPTZ;
        RETURN;
    END IF;
    
    v_expires := NOW() + (p_ttl_minutes || ' minutes')::INTERVAL;
    
    INSERT INTO concurrency_leases (
        namespace_id, account_id, resource_type_code, resource_scope, session_token, expires_at
    ) VALUES (
        v_namespace, p_account_id, p_resource_type, p_resource_scope, p_session_token, v_expires
    )
    RETURNING concurrency_leases.lease_id INTO v_lease_id;
    
    SELECT * INTO v_check FROM fn_check_entitlement(p_account_id, p_resource_type, p_resource_scope, 0);
    
    IF v_check.quantity_used > v_check.quantity_allowed AND v_check.decision = 'deny' THEN
        UPDATE concurrency_leases SET released_at = NOW() WHERE concurrency_leases.lease_id = v_lease_id;
        RETURN QUERY SELECT FALSE, NULL::UUID, 'deny'::VARCHAR(16), 'Concurrent limit reached'::VARCHAR(255), NULL::TIMESTAMPTZ;
        RETURN;
    END IF;
    
    RETURN QUERY SELECT TRUE, v_lease_id, v_check.decision, v_check.reason, v_expires;
END;
$$;

-- fn_release_lease
CREATE OR REPLACE FUNCTION fn_release_lease(p_lease_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE concurrency_leases SET released_at = NOW() WHERE lease_id = p_lease_id AND released_at IS NULL;
    RETURN FOUND;
END;
$$;

-- fn_heartbeat_lease
CREATE OR REPLACE FUNCTION fn_heartbeat_lease(p_lease_id UUID, p_extend_minutes INT DEFAULT 60)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE concurrency_leases
    SET last_heartbeat = NOW(), expires_at = NOW() + (p_extend_minutes || ' minutes')::INTERVAL
    WHERE lease_id = p_lease_id AND released_at IS NULL AND expires_at > NOW();
    RETURN FOUND;
END;
$$;

-- fn_meter_consumption
CREATE OR REPLACE FUNCTION fn_meter_consumption(
    p_idempotency_key   VARCHAR(255),
    p_account_id        UUID,
    p_resource_type     VARCHAR(64),
    p_quantity          NUMERIC(18,6),
    p_unit_code         VARCHAR(32) DEFAULT NULL,
    p_resource_scope    VARCHAR(128) DEFAULT NULL,
    p_occurred_at       TIMESTAMPTZ DEFAULT NOW(),
    p_period_start      TIMESTAMPTZ DEFAULT NULL,
    p_period_end        TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id      UUID;
    v_namespace     VARCHAR(64);
    v_unit          VARCHAR(32);
BEGIN
    SELECT namespace_id INTO v_namespace FROM accounts WHERE account_id = p_account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account not found: %', p_account_id;
    END IF;
    
    IF p_unit_code IS NULL THEN
        SELECT default_unit_code INTO v_unit FROM resource_types WHERE resource_type_code = p_resource_type;
    ELSE
        v_unit := p_unit_code;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM resource_type_allowed_units
        WHERE resource_type_code = p_resource_type AND unit_code = v_unit
    ) THEN
        RAISE EXCEPTION 'Unit % not allowed for resource type %', v_unit, p_resource_type;
    END IF;
    
    INSERT INTO consumption_ledger (
        idempotency_key, namespace_id, account_id, resource_type_code, resource_scope,
        quantity, unit_code, occurred_at, period_start, period_end
    ) VALUES (
        p_idempotency_key, v_namespace, p_account_id, p_resource_type, p_resource_scope,
        p_quantity, v_unit, p_occurred_at, p_period_start, p_period_end
    )
    RETURNING event_id INTO v_event_id;
    
    RETURN v_event_id;
END;
$$;

-- fn_provision_plan_entitlements
CREATE OR REPLACE FUNCTION fn_provision_plan_entitlements(
    p_account_id    UUID,
    p_plan_id       VARCHAR(64),
    p_start_date    TIMESTAMPTZ DEFAULT NOW()
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_template      RECORD;
    v_count         INT := 0;
    v_namespace     VARCHAR(64);
    v_end_date      TIMESTAMPTZ;
BEGIN
    SELECT namespace_id INTO v_namespace FROM accounts WHERE account_id = p_account_id;
    
    FOR v_template IN SELECT * FROM plan_entitlement_templates WHERE plan_id = p_plan_id
    LOOP
        IF v_template.duration_days IS NOT NULL THEN
            v_end_date := p_start_date + (v_template.duration_days || ' days')::INTERVAL;
        ELSE
            v_end_date := NULL;
        END IF;
        
        INSERT INTO entitlements (
            namespace_id, account_id, resource_type_code, resource_scope,
            limit_kind_code, quantity_allowed, unit_code, window_type_code, window_anchor,
            effective_start, effective_end, plan_id, template_id
        ) VALUES (
            v_namespace, p_account_id, v_template.resource_type_code, v_template.resource_scope,
            v_template.limit_kind_code, v_template.quantity_allowed, v_template.unit_code,
            v_template.window_type_code, p_start_date, p_start_date, v_end_date, p_plan_id, v_template.template_id
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_accounts_updated BEFORE UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();
CREATE TRIGGER trg_entitlements_updated BEFORE UPDATE ON entitlements FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();
CREATE TRIGGER trg_control_rules_updated BEFORE UPDATE ON control_rules FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();
CREATE TRIGGER trg_plans_updated BEFORE UPDATE ON plans FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- Prevent ledger modifications (append-only)
CREATE OR REPLACE FUNCTION fn_prevent_ledger_modification()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Consumption ledger is append-only. Cannot update events.';
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Consumption ledger is append-only. Cannot delete events.';
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_ledger_append_only
    BEFORE UPDATE OR DELETE ON consumption_ledger
    FOR EACH ROW EXECUTE FUNCTION fn_prevent_ledger_modification();

-- Validate consumption unit
CREATE OR REPLACE FUNCTION fn_validate_consumption_unit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM resource_type_allowed_units
        WHERE resource_type_code = NEW.resource_type_code AND unit_code = NEW.unit_code
    ) THEN
        RAISE EXCEPTION 'Unit % not allowed for resource type %', NEW.unit_code, NEW.resource_type_code;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_consumption_unit
    BEFORE INSERT ON consumption_ledger
    FOR EACH ROW EXECUTE FUNCTION fn_validate_consumption_unit();

-- Validate entitlement unit
CREATE OR REPLACE FUNCTION fn_validate_entitlement_unit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM resource_type_allowed_units
        WHERE resource_type_code = NEW.resource_type_code AND unit_code = NEW.unit_code
    ) THEN
        RAISE EXCEPTION 'Unit % not allowed for resource type %', NEW.unit_code, NEW.resource_type_code;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_entitlement_unit
    BEFORE INSERT OR UPDATE ON entitlements
    FOR EACH ROW EXECUTE FUNCTION fn_validate_entitlement_unit();

-- Validate account hierarchy (max 1 level)
CREATE OR REPLACE FUNCTION fn_validate_account_hierarchy()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_parent_has_parent BOOLEAN;
BEGIN
    IF NEW.parent_account_id IS NOT NULL THEN
        SELECT (parent_account_id IS NOT NULL) INTO v_parent_has_parent
        FROM accounts WHERE account_id = NEW.parent_account_id;
        
        IF v_parent_has_parent THEN
            RAISE EXCEPTION 'Maximum account hierarchy depth is 1';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_account_hierarchy
    BEFORE INSERT OR UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION fn_validate_account_hierarchy();

-- Audit entitlement changes
CREATE OR REPLACE FUNCTION fn_audit_entitlement_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO entitlements_audit (entitlement_id, operation, new_values)
        VALUES (NEW.entitlement_id, 'INSERT', to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO entitlements_audit (entitlement_id, operation, old_values, new_values)
        VALUES (NEW.entitlement_id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_entitlement
    AFTER INSERT OR UPDATE ON entitlements
    FOR EACH ROW EXECUTE FUNCTION fn_audit_entitlement_change();
