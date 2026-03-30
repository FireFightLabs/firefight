# Integration Capability Implementation Plan

## Context

This document translates `docs/INTEGRATION_CAPABILITY_PLAN.md` into a concrete Rails implementation approach.

The goal is to build one integration subsystem that:

- supports both `api` and `mcp` providers
- maps provider capabilities into Firefight Actions
- lets Actions become assignable permissions
- evaluates invoke and approve policy consistently
- executes through one audit-friendly pipeline

## Guiding Principles

- Firefight exposes Actions, not raw provider tools
- APIs and MCPs share one Action model
- permissions are role-first, with user overrides
- targeting is catalogue-aware and typed
- implementation starts in-app under `Integrations`
- extraction to an engine is deferred until the model stabilizes

## High-Level Build Order

1. Provider and capability persistence
2. Action mapping and registration
3. Capability-based permission integration
4. Policy evaluator
5. Approval workflow
6. Unified execution pipeline
7. Incident timeline and audit logging
8. UI and admin flows

## Phase 1: Data Model

### Tables

Create these tables first:

- `integration_providers`
- `integration_capabilities`
- `integration_actions`
- `integration_action_policy_rules`
- `integration_action_executions`
- `integration_action_approvals`

### `integration_providers`

Purpose:

- store workspace-level provider connections
- support both `api` and `mcp`

Suggested columns:

```ruby
create_table :integration_providers do |t|
  t.references :workspace, null: false, foreign_key: true
  t.string :name, null: false
  t.string :provider_type, null: false
  t.string :slug, null: false
  t.text :auth_ciphertext
  t.jsonb :config, null: false, default: {}
  t.boolean :enabled, null: false, default: true
  t.datetime :last_discovered_at
  t.timestamps
end

add_index :integration_providers, [ :workspace_id, :slug ], unique: true
add_index :integration_providers, [ :workspace_id, :provider_type ]
```

Notes:

- `slug` gives a stable workspace-local identifier
- `auth_ciphertext` should use the app's existing encrypted attributes approach if available
- `config` stores provider-specific settings

### `integration_capabilities`

Purpose:

- store raw provider capabilities
- represent either discovered MCP tools or configured API actions

Suggested columns:

```ruby
create_table :integration_capabilities do |t|
  t.references :integration_provider, null: false, foreign_key: true
  t.string :source_type, null: false
  t.string :key, null: false
  t.string :remote_name, null: false
  t.text :description
  t.jsonb :input_schema, null: false, default: {}
  t.jsonb :metadata, null: false, default: {}
  t.boolean :active, null: false, default: true
  t.timestamps
end

add_index :integration_capabilities,
  [ :integration_provider_id, :key ],
  unique: true,
  name: "idx_integration_capabilities_provider_key"
```

Notes:

- `source_type` is `mcp_tool` or `api_action`
- `key` is Firefight-stable, `remote_name` is provider-facing

### `integration_actions`

Purpose:

- store Firefight-safe, human-readable Actions derived from capabilities

Suggested columns:

```ruby
create_table :integration_actions do |t|
  t.references :workspace, null: false, foreign_key: true
  t.references :integration_provider, null: false, foreign_key: true
  t.references :integration_capability, null: false, foreign_key: true
  t.string :slug, null: false
  t.string :name, null: false
  t.text :description
  t.string :category, null: false
  t.string :execution_mode, null: false
  t.string :approval_policy, null: false
  t.jsonb :input_schema, null: false, default: {}
  t.jsonb :input_defaults, null: false, default: {}
  t.jsonb :input_constraints, null: false, default: {}
  t.jsonb :target_schema, null: false, default: {}
  t.boolean :enabled, null: false, default: true
  t.timestamps
end

add_index :integration_actions, [ :workspace_id, :slug ], unique: true
add_index :integration_actions, [ :workspace_id, :execution_mode ]
```

Notes:

- `target_schema` describes allowed catalogue entity types
- `slug` is used to derive capability keys

### `integration_action_policy_rules`

Purpose:

- define allow and deny rules for invoke permissions and approval requirements

Suggested columns:

```ruby
create_table :integration_action_policy_rules do |t|
  t.references :workspace, null: false, foreign_key: true
  t.references :integration_action, null: false, foreign_key: true
  t.string :effect, null: false
  t.string :principal_type, null: false
  t.string :principal_id, null: false
  t.jsonb :target_constraints, null: false, default: {}
  t.jsonb :environment_constraints, null: false, default: []
  t.boolean :requires_approval, null: false, default: false
  t.timestamps
end

add_index :integration_action_policy_rules,
  [ :integration_action_id, :principal_type, :principal_id ],
  name: "idx_action_policy_rules_lookup"
```

Notes:

- `principal_type` starts with `user`, `workspace_role`, `catalogue_team`
- keep `principal_id` string-based for flexibility across principal types

### `integration_action_executions`

Purpose:

- record every execution attempt and outcome

Suggested columns:

```ruby
create_table :integration_action_executions do |t|
  t.references :workspace, null: false, foreign_key: true
  t.references :integration_action, null: false, foreign_key: true
  t.references :incident, foreign_key: true
  t.references :requested_by_membership, foreign_key: { to_table: :workspace_memberships }
  t.references :approved_by_membership, foreign_key: { to_table: :workspace_memberships }
  t.string :status, null: false
  t.jsonb :targets, null: false, default: {}
  t.jsonb :input, null: false, default: {}
  t.jsonb :policy_snapshot, null: false, default: {}
  t.jsonb :result, null: false, default: {}
  t.datetime :executed_at
  t.timestamps
end

add_index :integration_action_executions, [ :workspace_id, :created_at ]
add_index :integration_action_executions, [ :incident_id, :created_at ]
```

### `integration_action_approvals`

Purpose:

- track approval requests and decisions

Suggested columns:

```ruby
create_table :integration_action_approvals do |t|
  t.references :workspace, null: false, foreign_key: true
  t.references :integration_action_execution, null: false, foreign_key: true
  t.references :requested_by_membership, foreign_key: { to_table: :workspace_memberships }
  t.references :approved_by_membership, foreign_key: { to_table: :workspace_memberships }
  t.string :status, null: false
  t.text :reason
  t.timestamps
end

add_index :integration_action_approvals,
  [ :integration_action_execution_id, :status ],
  name: "idx_action_approvals_execution_status"
```

## Phase 2: Rails Models

Create models under `app/models/integrations/`.

Recommended classes:

- `Integrations::Provider`
- `Integrations::Capability`
- `Integrations::Action`
- `Integrations::ActionPolicyRule`
- `Integrations::ActionExecution`
- `Integrations::ActionApproval`

### Example model concerns

- validations for enums and required jsonb shapes
- scopes for `enabled`, `active`, `provider_type`, and `execution_mode`
- helper methods to derive capability keys from an Action slug

Example enum constants:

```ruby
class Integrations::Action < ApplicationRecord
  EXECUTION_MODE_READ = "read"
  EXECUTION_MODE_WRITE = "write"
  EXECUTION_MODE_DANGEROUS = "dangerous"

  APPROVAL_POLICY_AUTO = "auto"
  APPROVAL_POLICY_MANUAL = "manual"
  APPROVAL_POLICY_DISABLED = "disabled"
end
```

Follow the existing app pattern of using constants rather than raw strings throughout the codebase.

## Phase 3: Service Layer Structure

Create service objects under `app/services/integrations/`.

Recommended layout:

```text
app/services/integrations/
  providers/
  discovery/
  actions/
  policy/
  approvals/
  execution/
  audit/
```

Recommended services:

- `Integrations::Providers::Connect`
- `Integrations::Discovery::DiscoverCapabilities`
- `Integrations::Actions::MapCapability`
- `Integrations::Actions::RegisterCapabilities`
- `Integrations::Policy::Evaluator`
- `Integrations::Approvals::RequestApproval`
- `Integrations::Approvals::Approve`
- `Integrations::Execution::ExecuteAction`
- `Integrations::Execution::ApiExecutor`
- `Integrations::Execution::McpExecutor`
- `Integrations::Audit::RecordExecution`

## Phase 4: Capability Discovery and Registration

### MCP path

Build `Integrations::Discovery::DiscoverCapabilities` to:

1. load provider connection details
2. call the MCP discovery endpoint
3. normalize returned tools
4. upsert `Integrations::Capability` records

Expected normalized attributes:

- stable `key`
- `remote_name`
- description
- input schema
- metadata

### API path

Build static provider templates for curated API actions.

For MVP, avoid a totally free-form API builder. Use code-defined templates or admin-defined config with limited options.

Examples:

- `fetch_service_logs`
- `get_recent_deployments`
- `restart_service`
- `rollback_deploy`

These still become `Integrations::Capability` records so both provider types converge before Action mapping.

## Phase 5: Action Mapping

Build `Integrations::Actions::MapCapability`.

Responsibilities:

- assign a Firefight action slug
- generate a human-readable name
- choose category
- classify execution mode
- set approval policy defaults
- apply target schema defaults

Example mapping rules:

- tools matching `get_*`, `list_*`, `fetch_*` default to `read`
- tools matching `redeploy_*`, `restart_*`, `rollback_*` default to `write`
- tools matching `delete_*`, `failover_*`, `shutdown_*` default to `dangerous`

Allow admins to override the generated defaults later.

## Phase 6: Capability Registration for Permissions

When an Action is created or enabled, automatically register permissionable capability keys.

At minimum:

- `action.<slug>.invoke`
- `action.<slug>.approve`

Implementation options:

- if the app already has a capability or RBAC model, integrate there directly
- otherwise create a lightweight registration table later if needed

Important behavior:

- capability registration is automatic
- assignment to roles is still explicit

This ensures every Action appears automatically in role configuration.

## Phase 7: Policy Evaluator

Build `Integrations::Policy::Evaluator` with a stable contract.

Input:

- actor membership
- action
- incident
- target context
- input payload

Output:

```ruby
PolicyDecision = Struct.new(
  :allowed,
  :requires_approval,
  :reasons,
  keyword_init: true
)
```

Responsibilities:

1. confirm Action is enabled
2. load matching policy rules
3. resolve actor principals
4. apply explicit deny rules first
5. apply explicit allow rules
6. validate target constraints
7. validate environment constraints
8. determine whether approval is required

### Principal resolution

For MVP, resolve these principals:

- current user id
- workspace roles for the membership
- linked catalogue team ids, if available

User-specific rules should act as overrides, but role-based rules should be the main configuration path.

## Phase 8: Approval Flow

Build approval services that work independently of provider type.

### `Integrations::Approvals::RequestApproval`

Responsibilities:

- create an `ActionExecution` in pending state
- create an `ActionApproval` request record
- return approval metadata to the caller

### `Integrations::Approvals::Approve`

Responsibilities:

- validate approver capability and policy
- update approval record
- trigger the waiting execution

For MVP, approval can start as a simple app-side state transition with later Slack or UI hooks.

## Phase 9: Unified Execution Pipeline

Build `Integrations::Execution::ExecuteAction` as the main entry point.

Suggested flow:

1. load Action
2. evaluate policy
3. create execution record
4. request approval if needed
5. execute via provider-specific executor
6. normalize result
7. persist result and audit snapshot
8. record incident timeline event

Suggested request object:

```ruby
ActionRequest = Struct.new(
  :action,
  :incident,
  :requested_by,
  :targets,
  :input,
  keyword_init: true
)
```

### API executor

`Integrations::Execution::ApiExecutor` should:

- resolve the HTTP action definition
- render endpoint and parameters from `targets` and `input`
- execute request with timeout and error handling
- normalize response into a common result shape

### MCP executor

`Integrations::Execution::McpExecutor` should:

- resolve provider and remote tool name
- invoke the MCP tool with validated inputs
- normalize response into the same result shape

Both executors should return a normalized hash or PORO, not provider-specific payloads.

## Phase 10: Catalogue-Aware Target Resolution

Use the system catalogue as the source of typed execution targets.

For MVP, the evaluator and execution layer should accept generic typed targets:

```ruby
{
  "service" => "catalog_entry_id_1",
  "environment" => "catalog_entry_id_2"
}
```

Implementation rules:

- validate target types against `integration_actions.target_schema`
- store target ids in execution records
- resolve display names only when presenting results
- avoid hardcoding service, team, or environment as special-case architecture

This keeps the design aligned with future catalogue expansion.

## Phase 11: Incident Timeline and Audit Hooks

Each execution should create timeline-visible events and durable audit records.

Recommended event points:

- action requested
- action denied
- approval requested
- approval granted
- approval denied
- execution started
- execution succeeded
- execution failed

Suggested implementation:

- add integration execution events through a service layer, not model callbacks
- if incident-specific, attach to the incident via a new timeline event type or dedicated execution record presenter

## Phase 12: UI and Admin Flows

MVP admin screens should support:

- connect provider
- inspect discovered or registered capabilities
- map or review generated Actions
- edit Action defaults
- configure who can invoke and approve Actions

MVP incident UI should support:

- showing suggested Actions
- showing approval-required state
- showing execution history in the incident timeline

## Suggested File Layout

```text
app/models/integrations/provider.rb
app/models/integrations/capability.rb
app/models/integrations/action.rb
app/models/integrations/action_policy_rule.rb
app/models/integrations/action_execution.rb
app/models/integrations/action_approval.rb

app/services/integrations/providers/connect.rb
app/services/integrations/discovery/discover_capabilities.rb
app/services/integrations/actions/map_capability.rb
app/services/integrations/actions/register_capabilities.rb
app/services/integrations/policy/evaluator.rb
app/services/integrations/approvals/request_approval.rb
app/services/integrations/approvals/approve.rb
app/services/integrations/execution/execute_action.rb
app/services/integrations/execution/api_executor.rb
app/services/integrations/execution/mcp_executor.rb
app/services/integrations/audit/record_execution.rb
```

## Testing Plan

### Model tests

- validations for provider, capability, Action, and policy records
- enum constant coverage
- uniqueness and scope behavior

### Service tests

- MCP discovery upserts capabilities correctly
- API capability registration creates the right records
- Action mapping classifies execution mode correctly
- policy evaluator returns expected decisions for role and user rules
- approval request path creates pending execution records
- API executor and MCP executor normalize results consistently

### Integration tests

- connecting a provider and discovering capabilities
- mapping a capability into an Action
- assigning invoke capability to a role
- denying execution for unauthorized actor
- requiring approval for a write Action
- successful execution appears in the incident timeline

## MVP Scope Recommendation

Start with a narrow slice that proves the model.

Recommended MVP:

- one API provider
- one MCP provider
- one read Action
- one write Action
- role-based invoke permissions
- role-based approve permissions
- user override support
- catalogue-backed target validation for one or two target types
- audit logging and incident timeline output

Suggested first Actions:

- `View Logs`
- `Redeploy Service`

These cover:

- safe read execution
- approval-gated write execution
- typed targeting
- policy checks
- provider abstraction

## Deferred Work

Do not do these in the first implementation:

- generic external gem extraction
- separate policy engine extraction
- free-form end-user API action builder
- overly complex relationship-aware targeting rules
- AI multi-step orchestration across many Actions

These can come after the Action, policy, and execution model is proven.

## Recommended Sequence of Pull Requests

1. Schema and models for providers, capabilities, and Actions
2. Discovery and static capability registration
3. Action mapping and capability registration
4. Policy rules and evaluator
5. Approval records and workflow
6. Unified execution service with API and MCP executors
7. Incident timeline integration and admin UI

## Summary

This implementation plan keeps the system simple where it should be simple:

- one provider model
- one capability model
- one Action layer
- one policy contract
- one approval path
- one execution pipeline

At the same time, it leaves the right seams for later expansion into richer catalogue targeting, more advanced RBAC, and possible engine extraction.
