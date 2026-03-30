# Integration Capability Plan

## Context

Firefight needs a single integration model that supports both traditional APIs and MCP providers without exposing provider-specific complexity to users or the AI layer.

The core product idea is:

- providers expose raw capabilities
- Firefight maps those capabilities to structured Actions
- users and AI interact only with Actions
- policy, approvals, constraints, and audit logging sit between Action selection and execution

This keeps integrations incident-aware, safe, and flexible enough for future service, team, and environment modeling.

## Goals

- Support two provider types: normal APIs and MCPs
- Normalize both into one internal Action layer
- Make Actions assignable as capabilities in the Firefight permission system
- Support flexible targeting against catalogue entities
- Keep the initial implementation in-app under a clear `Integrations` namespace
- Leave room for future extraction into an internal Rails engine if the subsystem stabilizes

## Non-goals

- Exposing raw MCP tools directly to end users or the AI
- Building a fully generic standalone policy engine on day one
- Hardcoding service, team, and environment as the only targeting dimensions
- Extracting this to a gem before the product model is proven

## Product Positioning

Firefight should describe this system as an integration capability platform, not an MCP feature.

That means:

- `api` providers cover REST, GraphQL, internal HTTP services, and webhook-driven integrations
- `mcp` providers cover dynamically discovered tool-based integrations
- both become Firefight Actions
- AI interacts with Firefight Actions, never raw provider interfaces

## Core Concepts

### 1. Integration Provider

An external system Firefight can connect to.

Examples:

- Datadog API
- Railway API
- Grafana API
- Internal deployment API
- Railway MCP server
- Internal MCP server

```ts
type IntegrationProvider = {
  id: string
  workspace_id: string
  name: string
  provider_type: "api" | "mcp"
  auth: Record<string, unknown>
  config: Record<string, unknown>
  enabled: boolean
}
```

### 2. Provider Capability

A raw operation exposed by a provider.

- For MCP, this usually comes from discovery
- For APIs, this is defined by Firefight configuration or templates

```ts
type ProviderCapability = {
  id: string
  provider_id: string
  source_type: "mcp_tool" | "api_action"
  key: string
  remote_name: string
  description: string
  input_schema: Record<string, unknown>
  metadata: Record<string, unknown>
}
```

Examples:

- MCP tool `redeploy_service`
- API action `POST /services/:id/redeploy`
- API action `GET /logs/search`

### 3. Action

The Firefight-safe representation of a capability.

This is the layer used by:

- users
- AI
- policy evaluation
- approvals
- audit logging

```ts
type Action = {
  id: string
  provider_id: string
  capability_id: string
  slug: string
  name: string
  description: string
  category: "logs" | "metrics" | "infra" | "code" | "custom"
  execution_mode: "read" | "write" | "dangerous"
  approval_policy: "auto" | "manual" | "disabled"
  input_schema: Record<string, unknown>
  input_defaults: Record<string, unknown>
  input_constraints: Record<string, unknown>
  enabled: boolean
}
```

Examples:

- `View Logs`
- `View Deployments`
- `Redeploy Service`
- `Rollback Deploy`

### 4. Action Capability

Each Action automatically becomes a permissionable capability inside Firefight.

At minimum, each Action should produce:

- `action.<slug>.invoke`
- `action.<slug>.approve`

Examples:

- `action.view_logs.invoke`
- `action.redeploy_service.invoke`
- `action.redeploy_service.approve`

This keeps the permission model aligned with the Action model.

## Provider Ingestion Paths

### A. MCP Discovery

For MCP providers:

1. connect to provider
2. discover tools from the MCP server
3. store raw tools as `ProviderCapability` records
4. map them into Firefight `Action` records

Example:

| Raw MCP tool | Firefight Action |
|---|---|
| `get_logs` | `View Logs` |
| `list_deployments` | `View Deployments` |
| `redeploy_service` | `Redeploy Service` |

### B. Static API Action Definitions

For API providers:

1. connect to provider
2. define actions from a Firefight-managed template or admin configuration
3. store those definitions as `ProviderCapability` records with `source_type: api_action`
4. map them into Firefight `Action` records

Example API actions:

- `fetch_service_logs`
- `get_recent_deployments`
- `restart_service`
- `rollback_deploy`

This gives Firefight both dynamic discovery and curated reliability.

## Catalogue-Aware Targeting

Actions should not be limited to hardcoded fields like `service`, `team`, or `environment`.

Instead, Actions should be able to target catalogue-backed entities in a typed way.

This allows workspaces to tie Actions to whatever they model in the catalogue, such as:

- services
- teams
- environments
- clusters
- regions
- repos
- databases
- tenants

### Action Target Schema

```ts
type ActionTargetSchema = {
  primary_target_types: string[]
  context_target_types?: string[]
  required_targets?: string[]
}
```

Examples:

- `Redeploy Service`
  - primary target types: `service`
  - context target types: `environment`, `team`
- `Run Failover`
  - primary target types: `cluster`
  - context target types: `environment`, `region`

### Action Target Input

```ts
type ActionTargetInput = {
  targets: Record<string, string>
}
```

Where each value is a catalogue entry id.

This gives Firefight a future-proof model without requiring every workspace to share the same exact taxonomy.

## Permissions, Approvals, and Constraints

The policy layer should be split into three concerns:

- `permissions`: who may invoke an Action
- `approvals`: who may approve an Action when approval is required
- `constraints`: which targets and inputs are allowed

### Why split these concerns

This makes the model flexible enough for rules like:

- any engineer can run read actions
- only SRE can invoke write actions in prod
- only the incident commander can approve dangerous actions
- only owners of a service can redeploy that service

## Principals

The system should support multiple principal types from day one.

Recommended initial set:

- `user`
- `workspace_role`
- `catalogue_team`

Future options:

- `incident_role`
- `on_call_schedule`
- `group`

## Default Access Model

Use role-based access as the default UX.

Support user-specific rules as exceptions or overrides.

Recommended defaults:

- `read` actions can be broadly allowed, but still policy-controlled
- `write` actions default to explicit allow only
- `dangerous` actions default to disabled or strict approval

This means Firefight should be:

- per role by default
- per user as an override

## Policy Rule Shape

```ts
type ActionPolicyRule = {
  id: string
  action_id: string
  effect: "allow" | "deny"
  principal_type: "user" | "workspace_role" | "catalogue_team"
  principal_id: string
  target_constraints?: {
    target_types?: string[]
    target_ids?: string[]
  }
  environment_constraints?: string[]
  requires_approval?: boolean
}
```

Example: only one user may redeploy services

```json
{
  "action_id": "redeploy-service",
  "effect": "allow",
  "principal_type": "user",
  "principal_id": "user_123",
  "requires_approval": false
}
```

Example: only platform role may redeploy in prod

```json
{
  "action_id": "redeploy-service",
  "effect": "allow",
  "principal_type": "workspace_role",
  "principal_id": "platform_engineer",
  "environment_constraints": ["prod"],
  "requires_approval": true
}
```

## Policy Evaluation Contract

The initial implementation should use a simple internal evaluator with a stable decision contract.

```ts
type PolicyDecision = {
  allowed: boolean
  requires_approval: boolean
  reasons: string[]
}
```

Evaluation order should be predictable:

1. action enabled check
2. explicit deny for matching principals
3. explicit allow for matching principals
4. target and environment constraint checks
5. approval requirement checks
6. return final decision

This is enough for an MVP and gives a clean seam for future improvements.

## Execution Flow

```text
Provider (API or MCP)
        ↓
Capability discovery or registration
        ↓
ProviderCapability
        ↓
Action mapping
        ↓
Firefight Action registry
        ↓
Policy evaluator
        ↓
Approval flow, if required
        ↓
Execution adapter
        ↓
Normalized ActionResult
        ↓
Incident timeline + audit log
```

### Incident-time flow

```text
1. Incident exists or is created
2. AI or user selects an Action
3. Firefight resolves target context from incident + catalogue
4. Policy evaluator checks invoke permissions
5. Firefight requests approval if required
6. Firefight executes via provider adapter
7. Firefight stores result and logs it in the incident timeline
```

## Execution Adapters

Firefight should have a normalized execution contract for all providers.

Do not call raw provider methods directly from product code.

```ts
type ActionExecutionRequest = {
  action_id: string
  incident_id?: string
  actor_id: string
  targets: Record<string, string>
  input: Record<string, unknown>
}

type ActionResult = {
  status: "succeeded" | "failed"
  summary: string
  output: Record<string, unknown>
  external_refs?: Array<{ label: string; url: string }>
}
```

Example adapter contract:

```ts
async function executeAction(request: ActionExecutionRequest): Promise<ActionResult> {
  // resolve provider and capability
  // execute via API or MCP adapter
  // normalize result
}
```

Implementation note:

- MCP adapter executes remote tools
- API adapter executes configured HTTP actions
- both return the same `ActionResult`

## Incident Timeline and Audit Logging

Every execution attempt should be logged.

Examples:

```text
[12:01] Incident created
[12:02] AI analyzed logs
[12:03] Suggested redeploy service
[12:04] Uros requested Redeploy Service for api-prod
[12:04] Approval required from SRE lead
[12:05] Alice approved Redeploy Service
[12:05] Railway redeployed api-prod
```

Audit entries should capture:

- actor
- action
- target context
- inputs used
- policy decision
- approver, if any
- execution result
- provider references

This supports:

- debugging
- security review
- incident review
- postmortems

## AI Integration Rules

The AI layer should interact only with Firefight Actions.

The AI should never see or call raw MCP tools or arbitrary provider methods.

AI rules:

- may auto-run allowed `read` actions
- may suggest `write` and `dangerous` actions
- must respect policy decisions and approval requirements
- should use incident context and catalogue targets when constructing requests

This keeps AI behavior consistent regardless of provider type.

## Guardrails

Required safeguards:

- timeouts for remote execution
- retries only where safe
- rate limiting
- scoped credentials
- encrypted provider secrets
- per-action policy checks
- approval logging
- full execution audit trail
- input validation against Action schema
- output normalization before displaying to users or AI

## Architecture Placement

The first implementation should stay inside the main app under a dedicated namespace.

Recommended namespaces:

```text
app/models/integrations/
app/services/integrations/
app/services/integrations/providers/
app/services/integrations/discovery/
app/services/integrations/actions/
app/services/integrations/policy/
app/services/integrations/execution/
app/services/integrations/approvals/
```

This gives a strong internal boundary without premature extraction.

## Should this be a gem or engine?

### Recommendation now

Do not make this a gem yet.

Reasons:

- the model is still evolving
- Actions, incidents, approvals, and timeline logging are Firefight-specific
- early extraction would force abstractions before the product is proven

### Better path

1. build it in-app under `Integrations`
2. keep interfaces clean and narrow
3. extract to an internal Rails engine later if the subsystem stabilizes

### Policy engine extraction

Also do not make policy its own separate engine yet.

Instead:

- keep policy inside `Integrations::Policy`
- expose a stable evaluator contract
- revisit extraction only if the same policy system is used across multiple unrelated domains

## Rails-Friendly Domain Model

Suggested first-pass models:

### Core records

- `IntegrationProvider`
- `IntegrationCapability`
- `IntegrationAction`
- `IntegrationActionCapability`
- `IntegrationActionPolicyRule`
- `IntegrationActionExecution`
- `IntegrationActionApproval`

### Suggested fields

#### `integration_providers`

- `workspace_id`
- `name`
- `provider_type` (`api`, `mcp`)
- `auth_ciphertext`
- `config` jsonb
- `enabled`
- `last_discovered_at`

#### `integration_capabilities`

- `integration_provider_id`
- `source_type` (`mcp_tool`, `api_action`)
- `key`
- `remote_name`
- `description`
- `input_schema` jsonb
- `metadata` jsonb
- `active`

#### `integration_actions`

- `workspace_id`
- `integration_provider_id`
- `integration_capability_id`
- `slug`
- `name`
- `description`
- `category`
- `execution_mode`
- `approval_policy`
- `input_schema` jsonb
- `input_defaults` jsonb
- `input_constraints` jsonb
- `target_schema` jsonb
- `enabled`

#### `integration_action_policy_rules`

- `workspace_id`
- `integration_action_id`
- `effect`
- `principal_type`
- `principal_id`
- `target_constraints` jsonb
- `environment_constraints` jsonb
- `requires_approval`

#### `integration_action_executions`

- `workspace_id`
- `integration_action_id`
- `incident_id`
- `requested_by_membership_id`
- `approved_by_membership_id`
- `status`
- `targets` jsonb
- `input` jsonb
- `policy_snapshot` jsonb
- `result` jsonb
- `executed_at`

#### `integration_action_approvals`

- `workspace_id`
- `integration_action_execution_id`
- `requested_by_membership_id`
- `approved_by_membership_id`
- `status`
- `reason`

## Capability Registration in RBAC

When an Action is created and enabled, it should automatically register permissionable capabilities.

At minimum:

- invoke capability
- approve capability

That means admins can immediately assign new Actions to roles without an extra setup step.

Recommended behavior:

1. provider capability is mapped to Action
2. Action is saved
3. Firefight auto-registers capability keys for that Action
4. those capability keys become assignable to roles
5. optional user-specific overrides can be added later

This creates a clean mental model:

- integrations create Actions
- Actions create capabilities
- roles grant capabilities
- policy decides whether execution is allowed now, later, or not at all

## Suggested Service Objects

Recommended service layer:

- `Integrations::Providers::Connect`
- `Integrations::Discovery::DiscoverCapabilities`
- `Integrations::Actions::MapCapability`
- `Integrations::Actions::RegisterCapabilities`
- `Integrations::Policy::Evaluator`
- `Integrations::Approvals::RequestApproval`
- `Integrations::Execution::ExecuteAction`
- `Integrations::Execution::ApiExecutor`
- `Integrations::Execution::McpExecutor`
- `Integrations::Audit::RecordExecution`

## Implementation Plan

### Phase 1: Provider and Capability Foundation

- add provider tables and models
- support `api` and `mcp` provider types
- store auth securely
- add capability discovery for MCP
- add static capability registration for API providers

Deliverable:

- workspace can connect providers and see raw capabilities

### Phase 2: Action Layer

- add `IntegrationAction` model
- map capabilities into Actions
- add categories and execution modes
- add target schema support backed by catalogue types
- add capability registration for permissions

Deliverable:

- workspace can see normalized Firefight Actions

### Phase 3: Policy and Approval Layer

- add policy rule model
- implement evaluator contract
- support principal types: `user`, `workspace_role`, `catalogue_team`
- add approval request records and approval flow
- auto-register `invoke` and `approve` capabilities

Deliverable:

- Firefight can answer who may invoke and who may approve each Action

### Phase 4: Execution Layer

- add `ExecuteAction` service
- add API executor
- add MCP executor
- normalize results into `ActionResult`
- enforce timeouts and logging

Deliverable:

- Firefight can execute Actions through one unified pipeline

### Phase 5: Incident and AI Integration

- let incidents carry target context from the catalogue
- let AI select and propose Actions
- auto-run safe read actions where allowed
- request approvals for writes and dangerous actions
- log all execution and approval events to the incident timeline

Deliverable:

- AI and users operate on the same safe Action system

## MVP Recommendation

Keep the first version narrow.

Recommended MVP:

- one API provider
- one MCP provider
- read, write, dangerous execution modes
- role-based invoke and approve permissions
- user-specific overrides
- basic catalogue-backed targeting using `service` and `environment` types if present
- incident timeline audit logging

Good first providers:

- API: Datadog, Railway, or internal deployment API
- MCP: Railway or internal MCP server

## Open Questions for Later

- should Actions be workspace-global or optionally scoped to incident type?
- should target constraints understand ownership relationships from the catalogue?
- should AI be allowed to chain multiple read actions automatically?
- how should capability discovery updates affect already customized Actions?
- when does `Integrations` deserve extraction into a Rails engine?

## Recommended Decisions

1. Keep the Action layer as the stable contract
2. Rename the concept from MCP integration plan to integration capability plan
3. Support two ingestion paths: dynamic MCP discovery and static API action definitions
4. Build one execution, policy, approval, and audit pipeline for both
5. Use catalogue-backed typed targeting rather than hardcoded service/team/environment fields
6. Use role-based permissions by default and user-specific rules as overrides
7. Automatically register Actions as permissionable capabilities
8. Keep the implementation in-app under `Integrations` until the design stabilizes

## Summary

Firefight should support both APIs and MCPs, but neither should define the product surface directly.

The product surface should be Firefight Actions:

- human-readable
- incident-aware
- catalogue-aware
- permissionable
- approval-aware
- fully auditable

That gives Firefight a flexible integration foundation that fits current needs and leaves room for future service, team, environment, and policy sophistication.
