-- ============================================================================
-- MEC SEED DATA
-- Run after schema.sql to populate lookup tables
-- ============================================================================

-- Account Types
INSERT INTO account_types (account_type_code, description, can_have_children) VALUES
    ('user', 'Individual user account', TRUE),
    ('organization', 'Organization/company account', TRUE),
    ('team', 'Team within an organization', FALSE);

-- Units
INSERT INTO units (unit_code, unit_category, description) VALUES
    ('count', 'discrete', 'Discrete count of items'),
    ('days', 'time', 'Calendar days'),
    ('hours', 'time', 'Hours'),
    ('minutes', 'time', 'Minutes'),
    ('tokens', 'compute', 'LLM tokens'),
    ('gpu_hours', 'compute', 'GPU compute hours'),
    ('bytes', 'storage', 'Bytes of storage'),
    ('requests', 'discrete', 'API requests');

-- Limit Kinds
INSERT INTO limit_kinds (limit_kind_code, description) VALUES
    ('cumulative', 'Total usage within a window (e.g., 100 runs/month)'),
    ('concurrency', 'Simultaneous active usage (e.g., 5 floating users)'),
    ('inventory', 'Count of owned items (e.g., 3 server configs)'),
    ('time_access', 'Access window (e.g., 30-day trial)');

-- Window Types
INSERT INTO window_types (window_type_code, description) VALUES
    ('calendar_month', 'Resets on 1st of each month'),
    ('billing_cycle', 'Resets on subscription anniversary'),
    ('rolling_30d', 'Rolling 30-day window'),
    ('rolling_7d', 'Rolling 7-day window'),
    ('none', 'No reset (lifetime cumulative)');

-- Limit Actions
INSERT INTO limit_actions (limit_action_code, description) VALUES
    ('block', 'Deny the action'),
    ('warn', 'Allow but notify user/admin'),
    ('grace', 'Allow within grace period/quantity'),
    ('overage', 'Allow and mark for overage billing');

-- ============================================================================
-- METRUM INSIGHTS SPECIFIC RESOURCE TYPES
-- ============================================================================

INSERT INTO resource_types (resource_type_code, namespace_id, description, default_unit_code, is_inventory, is_concurrency, is_time_bound) VALUES
    ('platform_access', 'default', 'Access to the platform', 'days', FALSE, FALSE, TRUE),
    ('concurrent_users', 'default', 'Floating user seats', 'count', FALSE, TRUE, FALSE),
    ('named_users', 'default', 'Named user seats', 'count', TRUE, FALSE, FALSE),
    ('benchmark_runs', 'default', 'Benchmark executions', 'count', FALSE, FALSE, FALSE),
    ('gpu_hours', 'default', 'GPU compute time', 'hours', FALSE, FALSE, FALSE),
    ('server_configs', 'default', 'Server configurations', 'count', TRUE, FALSE, FALSE),
    ('server_instances', 'default', 'Server instances', 'count', TRUE, FALSE, FALSE),
    ('ai_models', 'default', 'Registered AI models', 'count', TRUE, FALSE, FALSE),
    ('api_requests', 'default', 'API calls', 'requests', FALSE, FALSE, FALSE),
    ('reports_generated', 'default', 'Generated reports', 'count', FALSE, FALSE, FALSE),
    ('concurrent_jobs', 'default', 'Concurrent benchmark jobs', 'count', FALSE, TRUE, FALSE),
    ('llm_tokens', 'default', 'LLM tokens consumed', 'tokens', FALSE, FALSE, FALSE);

-- Allowed units for each resource type
INSERT INTO resource_type_allowed_units (resource_type_code, unit_code) VALUES
    ('platform_access', 'days'),
    ('concurrent_users', 'count'),
    ('named_users', 'count'),
    ('benchmark_runs', 'count'),
    ('gpu_hours', 'hours'),
    ('gpu_hours', 'gpu_hours'),
    ('server_configs', 'count'),
    ('server_instances', 'count'),
    ('ai_models', 'count'),
    ('api_requests', 'count'),
    ('api_requests', 'requests'),
    ('reports_generated', 'count'),
    ('concurrent_jobs', 'count'),
    ('llm_tokens', 'tokens'),
    ('llm_tokens', 'count');

-- ============================================================================
-- SAMPLE PLANS (Optional - remove in production if not needed)
-- ============================================================================

INSERT INTO plans (plan_id, namespace_id, plan_name, description, is_trial, trial_days, status) VALUES
    ('trial-14d', 'default', '14-Day Free Trial', 'Full access for 14 days', TRUE, 14, 'active'),
    ('starter', 'default', 'Starter', 'For small teams getting started', FALSE, NULL, 'active'),
    ('pro', 'default', 'Pro', 'For growing teams', FALSE, NULL, 'active'),
    ('enterprise', 'default', 'Enterprise', 'Custom enterprise solution', FALSE, NULL, 'active');

-- Trial plan templates
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code, duration_days) VALUES
    ('trial-14d', 'platform_access', 'time_access', NULL, 'days', NULL, 14),
    ('trial-14d', 'concurrent_users', 'concurrency', 2, 'count', NULL, 14),
    ('trial-14d', 'benchmark_runs', 'cumulative', 50, 'count', 'calendar_month', 14),
    ('trial-14d', 'gpu_hours', 'cumulative', 10, 'hours', 'calendar_month', 14),
    ('trial-14d', 'server_configs', 'inventory', 1, 'count', NULL, 14);

-- Starter plan templates
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code, duration_days) VALUES
    ('starter', 'concurrent_users', 'concurrency', 3, 'count', NULL, NULL),
    ('starter', 'benchmark_runs', 'cumulative', 100, 'count', 'calendar_month', NULL),
    ('starter', 'gpu_hours', 'cumulative', 25, 'hours', 'calendar_month', NULL),
    ('starter', 'server_configs', 'inventory', 2, 'count', NULL, NULL),
    ('starter', 'server_instances', 'inventory', 10, 'count', NULL, NULL);

-- Pro plan templates
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code, duration_days) VALUES
    ('pro', 'concurrent_users', 'concurrency', 10, 'count', NULL, NULL),
    ('pro', 'benchmark_runs', 'cumulative', 500, 'count', 'calendar_month', NULL),
    ('pro', 'gpu_hours', 'cumulative', 100, 'hours', 'calendar_month', NULL),
    ('pro', 'server_configs', 'inventory', 5, 'count', NULL, NULL),
    ('pro', 'server_instances', 'inventory', NULL, 'count', NULL, NULL);

-- Enterprise plan templates (generous defaults, typically customized per customer)
INSERT INTO plan_entitlement_templates (plan_id, resource_type_code, limit_kind_code, quantity_allowed, unit_code, window_type_code, duration_days) VALUES
    ('enterprise', 'concurrent_users', 'concurrency', NULL, 'count', NULL, NULL),
    ('enterprise', 'benchmark_runs', 'cumulative', 5000, 'count', 'calendar_month', NULL),
    ('enterprise', 'gpu_hours', 'cumulative', 1000, 'hours', 'calendar_month', NULL),
    ('enterprise', 'server_configs', 'inventory', NULL, 'count', NULL, NULL),
    ('enterprise', 'server_instances', 'inventory', NULL, 'count', NULL, NULL);

-- ============================================================================
-- DEFAULT CONTROL RULES
-- ============================================================================

INSERT INTO control_rules (namespace_id, rule_name, resource_type_code, limit_kind_code, limit_action_code, warn_at_percent, is_active) VALUES
    ('default', 'Default benchmark warning', 'benchmark_runs', 'cumulative', 'block', 80.00, TRUE),
    ('default', 'Default GPU hours warning', 'gpu_hours', 'cumulative', 'block', 80.00, TRUE),
    ('default', 'Concurrent users soft limit', 'concurrent_users', 'concurrency', 'block', 90.00, TRUE);

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Uncomment to verify seed data:
-- SELECT 'account_types' AS table_name, COUNT(*) AS row_count FROM account_types
-- UNION ALL SELECT 'units', COUNT(*) FROM units
-- UNION ALL SELECT 'limit_kinds', COUNT(*) FROM limit_kinds
-- UNION ALL SELECT 'window_types', COUNT(*) FROM window_types
-- UNION ALL SELECT 'limit_actions', COUNT(*) FROM limit_actions
-- UNION ALL SELECT 'resource_types', COUNT(*) FROM resource_types
-- UNION ALL SELECT 'plans', COUNT(*) FROM plans
-- UNION ALL SELECT 'plan_entitlement_templates', COUNT(*) FROM plan_entitlement_templates;
