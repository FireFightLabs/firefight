# Firefight Ability Gateway

> Unified design combining the Ability Gateway research doc and the Integration Layer doc.
> Predecessor docs preserved as `ABILITY_GATEWAY_ORIGINAL.md` and `INTEGRATION_LAYER.md`.

> Rails 8.1 · Solid Queue · Solid Cache · PostgreSQL · RubyLLM
> Last updated: April 2026

---

## What We're Building

A multi-tenant Ability Gateway embedded inside Firefight. It:

- Lets workspaces connect external services ("integrations") via MCP or REST connectors
- Auto-discovers tools from those integrations and surfaces them as "abilities"
- Receives inbound webhooks from external services and routes them to incident actions
- Enforces a scope-based permission system across all invocations
- Exposes abilities to four consumers: Slack, AI agents, workflows, and dashboard UI
- Supports human-in-the-loop confirmation for sensitive actions
- Uses Solid Queue for async discovery, credential refresh, health checks, and audit retention

**MCP is one connector type, not the system.** The gateway speaks "ability" at every layer above the connector. Whether an ability came from a Datadog MCP server or a Jira REST adapter is an implementation detail the rest of the system never needs to know.

**First-party integrations run on the same gateway layer as custom integrations.** Firefight's own Datadog integration is just an `Integration` record pointing at Datadog's MCP server — same model, same discovery, same ability store, same permission system. Every improvement to the gateway benefits first-party integrations automatically.

---

## Prior Art

| Project | Why it's relevant |
|---------|-------------------|
| **agentic-community/mcp-gateway-registry** | Scope-based RBAC, generation-based discovery sync, credential masking, client pooling |
| **fastmcp-gateway (Ultrathink)** | Progressive tool loading via 3 meta-tools — critical for AI tier |
| **IBM ContextForge** | Virtual server model, transport normalization |
| **MCP Mesh** | Multi-tenant org scoping |
| **Traefik Hub MCP Gateway** | Per-tool policy expressions |
| **Mintlify ChromaFs** | Tool-use over RAG pattern — agents explore via tools rather than consuming bulk context |

---

## Key Architectural Decisions

### 1. Cache Ability Schemas — Never Hit Connectors Live

Calling `tools/list` on an MCP server is a network call. Cache schemas on the `Ability` model at discovery time, serve from Solid Cache at invocation time. Invalidate on rediscovery.

```ruby
def ability_schema(ability_id)
  Rails.cache.fetch("ability:schema:#{ability_id}", expires_in: 5.minutes) do
    Ability.find(ability_id).input_schema
  end
end
```

### 2. Generation-Based Orphan Detection

On rediscovery, bump a generation counter. Stamp each found tool with the current generation. After the upsert loop, delete anything not in the current generation. Handles renames and removals cleanly.

```ruby
integration.increment!(:discovery_generation)
# upsert each tool with current generation...
integration.abilities.where.not(discovery_generation: integration.discovery_generation).destroy_all
```

### 3. Progressive Tool Loading for AI

Do not dump all ability schemas into the AI context. A workspace with 5 integrations x 20 tools = 100 schemas per request. Instead, give the AI 3 meta-tools and let it load schemas on demand:

- `find_ability(query)` — search abilities by natural language, returns names + descriptions only
- `get_ability_schema(ability_name)` — get full input schema for a specific ability
- `invoke_ability(ability_name, arguments)` — execute an ability

Base context cost = 3 small schemas regardless of integration count. This replaces the domain-based hierarchy approach from the original Integration Layer doc — it's simpler, more flexible, and proven in production (Ultrathink).

### 4. Namespaced Ability Keys

Two integrations can have identically named tools. The canonical identifier is always `integration_slug.tool_name`:

```ruby
def scope_key
  "#{integration.slug}.#{tool_name}"
end
```

Never use raw `tool_name` as an identifier.

### 5. Connection Pooling Per Connector

Cache connector clients via Solid Cache per integration. Reuse across invocations within the cache window.

```ruby
module Connectors::ClientPool
  def self.get(integration)
    key = "connector:client:#{integration.workspace_id}:#{integration.id}"
    Rails.cache.fetch(key, expires_in: 10.minutes) do
      case integration.connector_type
      when "mcp"  then Mcp::Client.new(integration.connector_url, integration.decrypted_credentials)
      when "rest" then Rest::Client.new(integration.connector_url, integration.decrypted_credentials)
      end
    end
  end
end
```

### 6. Credential Masking in Audit Logs

Never log raw credentials in `AbilityInvocation`. Sanitize sensitive keys before writing:

```ruby
SENSITIVE_KEYS = %w[token password secret key authorization api_key bearer].freeze

def sanitize(params)
  return params unless params.is_a?(Hash)
  params.transform_keys(&:to_s).transform_values { |v|
    SENSITIVE_KEYS.any? { |s| k.to_s.downcase.include?(s) } ? "[REDACTED]" : v
  }
end
```

---

## Data Model

### `integrations`

A connected external service instance. One workspace can have multiple integrations.

| Field | Type | Description |
|-------|------|-------------|
| `workspace_id` | FK | Owning workspace |
| `name` | string | Display name ("Datadog Production") |
| `slug` | string | URL-safe identifier, used in scope keys. Unique per workspace |
| `connector_type` | enum | `mcp`, `rest` |
| `connector_url` | string | MCP server URL or REST base API URL |
| `credentials` | encrypted | Auth credentials (encrypted at column level via Rails) |
| `status` | enum | `pending`, `discovering`, `connected`, `degraded`, `error`, `disabled` |
| `discovery_generation` | integer | Incremented on each discovery run (orphan detection) |
| `health_check_interval_minutes` | integer | Default 60 |
| `last_health_check_at` | datetime | |
| `last_discovered_at` | datetime | |
| `enabled` | boolean | Manual enable/disable |

**Status meanings:**

| Status | Meaning |
|--------|---------|
| `pending` | Just added, not yet connected |
| `discovering` | Discovery job is running |
| `connected` | Discovery succeeded, abilities are live |
| `degraded` | Last health check failed but was previously connected |
| `error` | Discovery failed or credentials invalid |
| `disabled` | Workspace admin manually disabled |

### `abilities`

A discoverable, invocable action on an integration.

| Field | Type | Description |
|-------|------|-------------|
| `integration_id` | FK | Parent integration |
| `tool_name` | string | Raw MCP/REST tool name |
| `display_name` | string | Human-readable name |
| `description` | text | What this tool does (used by AI `find_ability` search) |
| `description_override` | text | First-party override for better AI descriptions |
| `input_schema` | jsonb | JSON Schema defining expected parameters |
| `tool_config` | jsonb | Connector-specific execution config (see below) |
| `enabled` | boolean | Off by default for MCP-discovered tools until workspace enables |
| `confirmation_required` | boolean | Require human approval before executing (default: false) |
| `discovery_generation` | integer | Stamped during discovery for orphan detection |

**`effective_description`** — used everywhere the AI reads descriptions:
```ruby
def effective_description
  description_override.presence || description
end
```

**`scope_key`** — canonical namespaced identifier:
```ruby
def scope_key
  "ability:#{integration.slug}.#{tool_name}"
end
```

**tool_config by connector_type:**

```ruby
# mcp — tool_name is sufficient, MCP client calls tools/call with it
{}  # no extra config needed, tool_name is the identifier

# rest — HTTP request template
{
  method: "POST",
  path: "/rest/api/3/issue",
  headers: { "X-Custom" => "value" },
  payload_template: {                           # Liquid template, rendered with input params
    fields: {
      project: { key: "{{ project_key }}" },
      summary: "{{ summary }}"
    }
  },
  response_mapping: {                           # JSONPath to extract output fields
    id: "$.id",
    key: "$.key",
    url: "$.self"
  }
}
```

### `integration_webhook_endpoints`

Inbound webhook receiver. External services send events here, which trigger incident actions or ability invocations.

| Field | Type | Description |
|-------|------|-------------|
| `integration_id` | FK | Parent integration |
| `name` | string | Display name ("Datadog Alert Webhook") |
| `slug` | string | Unique slug (generates URL: `/webhooks/integrations/:slug`) |
| `secret` | string | HMAC signing secret for verification (auto-generated) |
| `active` | boolean | Enabled/disabled |
| `conditions` | jsonb | When to act (payload matching rules) |
| `action_type` | enum | `create_incident`, `update_incident`, `invoke_ability`, `trigger_workflow` |
| `action_config` | jsonb | What to do when triggered |
| `last_received_at` | datetime | |

**conditions format:**
```ruby
{
  rules: [
    { path: "$.alert.severity", operator: "equals", value: "critical" },
    { path: "$.alert.status", operator: "one_of", values: ["triggered", "re-triggered"] }
  ],
  match: "all"  # or "any"
}
```

**action_config by action_type:**
```ruby
# create_incident — maps payload fields to incident creation params
{
  field_mappings: {
    name: "{{ alert.title }}",
    summary: "{{ alert.message }}",
    severity_slug: "sev1",
    source: "datadog"
  }
}

# update_incident — finds incident and updates fields
{
  incident_lookup: { source: "{{ alert.incident_id }}" },
  field_mappings: { summary: "{{ alert.message }}" }
}

# invoke_ability — calls an ability with mapped params
{
  ability_scope_key: "datadog.acknowledge_alert",
  input_mappings: { alert_id: "{{ alert.id }}" }
}

# trigger_workflow — starts a workflow with mapped context
{
  workflow_class: "AlertResponseWorkflow",
  context_mappings: { alert_id: "{{ alert.id }}", severity: "{{ alert.severity }}" }
}
```

### `scopes`

Permission scopes for RBAC. Auto-created when integrations and abilities are created.

| Field | Type | Description |
|-------|------|-------------|
| `workspace_id` | FK | |
| `key` | string | `integration:datadog` or `ability:datadog.list_alerts` |
| `description` | text | |
| `scopeable` | polymorphic | Points to `Integration` or `Ability` |

Supports wildcard matching: `ability:datadog.*` matches `ability:datadog.list_alerts`.

### `roles`

| Field | Type | Description |
|-------|------|-------------|
| `workspace_id` | FK | |
| `name` | string | e.g., "Oncall Engineer", "Incident Commander" |
| `description` | text | |

### `role_scopes` (join)

| Field | Type |
|-------|------|
| `role_id` | FK |
| `scope_id` | FK |

### `role_assignments`

| Field | Type | Description |
|-------|------|-------------|
| `role_id` | FK | |
| `assignable` | polymorphic | `WorkspaceMembership`, `ApiKey`, etc. |

### `ability_invocations`

Audit log of every ability call.

| Field | Type | Description |
|-------|------|-------------|
| `ability_id` | FK | |
| `workspace_id` | FK | |
| `incident_id` | FK, optional | Related incident |
| `source` | string | `slack`, `ai_agent`, `workflow`, `dashboard` |
| `invoked_by` | string | Actor identifier |
| `input` | jsonb | Sanitized arguments (credentials stripped) |
| `output` | jsonb | Sanitized result |
| `status` | enum | `pending`, `awaiting_confirmation`, `confirmed`, `executing`, `succeeded`, `failed`, `rejected` |
| `duration_ms` | integer | |
| `error_message` | text | |
| `confirmed_by_id` | FK, optional | User who approved (if confirmation_required) |
| `confirmed_at` | datetime | |

---

## Permission & Scope System

Custom implementation — 4 tables, ~30 lines of Ruby. Pundit, CanCanCan, and Rolify are wrong abstractions for string scope matching with wildcards.

### PermissionChecker

```ruby
class PermissionChecker
  def initialize(actor)
    @actor = actor
  end

  def can?(required_scope_key)
    user_scope_keys.any? { |key| Scope.wildcard_match?(key, required_scope_key) }
  end

  def can_invoke?(ability)
    can?(ability.integration.scope_key) && can?(ability.scope_key)
  end

  private

  def user_scope_keys
    @user_scope_keys ||= Rails.cache.fetch(
      "permission:#{@actor.class.name}:#{@actor.id}",
      expires_in: 5.minutes
    ) do
      @actor.roles.flat_map(&:scopes).map(&:key).uniq
    end
  end
end
```

Cache invalidated on `RoleAssignment` create/destroy.

---

## Connector Layer

The only place in the codebase that knows connector type. Everything above operates on abilities.

```
Integrations::DiscoveryJob        — dispatches to correct service
  ├── Mcp::DiscoveryService       — calls tools/list via JSON-RPC
  └── Rest::DiscoveryService      — reads OpenAPI spec or static definition

Abilities::Invoker                — calls correct client
  ├── Mcp::Client                 — tools/call via JSON-RPC
  └── Rest::Client                — HTTP request per ability definition
```

### MCP Client

Handles JSON-RPC 2.0 protocol: `initialize` → `tools/list` → `tools/call`. Session initialized lazily on first call. Auth via bearer token or API key header.

### MCP Discovery Service

1. Set integration status to `discovering`
2. Increment `discovery_generation`
3. Call `tools/list`, upsert each tool as `Ability` with current generation
4. Delete abilities not in current generation (orphan detection)
5. Set status to `connected`
6. On error, set status to `error`

### REST Client

HTTP client that renders Liquid payload templates, makes requests, and applies JSONPath response mappings. Supports bearer, basic auth, API key header, and OAuth2.

### REST Discovery Service

Reads from OpenAPI spec (if integration provides one) or a static ability definition file. For first-party REST integrations (Fly.io, Render), Firefight maintains the static definition.

---

## Consumers

Abilities can be invoked from four places. All use the same `Abilities::Invoker` interface.

| Consumer | How it works |
|----------|-------------|
| **Slack** | `/firefight datadog.list_alerts status=triggered` — explicit invocation. AI tier: natural language routed through meta-tools |
| **AI agent** | Progressive tool loading: `find_ability` → `get_ability_schema` → `invoke_ability`. Used during incident analysis, postmortem generation |
| **Workflows** | SolidWorkflow step calls `Abilities::Invoker.call(ability, arguments, step, source: "workflow")`. If confirmation_required, step pauses |
| **Dashboard UI** | User clicks "Create Jira ticket" button → controller calls invoker → result shown in UI |

---

## Invocation Layer

### Abilities::Invoker

```ruby
module Abilities
  class Invoker
    def self.call(ability, arguments, actor, source:, incident: nil)
      new(ability, arguments, actor, source:, incident:).call
    end

    def call
      check_permissions!
      check_ability_enabled!

      invocation = create_invocation!(status: "pending")

      if @ability.confirmation_required?
        invocation.update!(status: "awaiting_confirmation")
        notify_for_confirmation(invocation)
        return invocation
      end

      execute!(invocation)
    end

    def self.confirm(invocation, confirmed_by:)
      invocation.update!(status: "confirmed", confirmed_by_id: confirmed_by.id, confirmed_at: Time.current)
      new(invocation.ability, invocation.input, confirmed_by, source: invocation.source).execute!(invocation)
    end

    def self.reject(invocation, rejected_by:)
      invocation.update!(status: "rejected", confirmed_by_id: rejected_by.id, confirmed_at: Time.current)
      invocation
    end

    def execute!(invocation)
      invocation.update!(status: "executing")
      started_at = Time.current

      client = Connectors::ClientPool.get(@ability.integration)
      result = client.call_tool(@ability.tool_name, @arguments)

      invocation.update!(
        output: sanitize(result),
        status: "succeeded",
        duration_ms: ((Time.current - started_at) * 1000).to_i
      )
      invocation
    rescue => e
      invocation.update!(
        status: "failed",
        error_message: e.message,
        duration_ms: ((Time.current - started_at) * 1000).to_i
      )
      raise
    end
  end
end
```

### Workflow Integration

SolidWorkflow steps call abilities through the invoker:

```ruby
def create_jira_ticket(workflow:, step:, input:)
  ability = workspace_ability(workflow, "jira.create_issue")
  invocation = Abilities::Invoker.call(
    ability,
    { summary: input["incident_name"], project: "OPS" },
    step,
    source: "workflow",
    incident: workflow.subject
  )

  if invocation.awaiting_confirmation?
    # Step pauses — will be resumed when user confirms via Slack/dashboard
    raise SolidWorkflow::StepPaused, "Awaiting confirmation for #{ability.scope_key}"
  end

  { ticket_id: invocation.output["id"], ticket_key: invocation.output["key"] }
end
```

---

## Inbound Webhooks

External services send events to Firefight via integration webhook endpoints. The gateway evaluates conditions, maps payload fields, and routes to the appropriate action.

### Flow

```
External service → POST /webhooks/integrations/:slug
  → IntegrationWebhooksController#receive
    → Find endpoint by slug
    → Verify HMAC-SHA256 signature
    → Parse JSON payload
    → Evaluate conditions against payload
    → If conditions match:
      → create_incident: IncidentLifecycleService.create(mapped_fields)
      → update_incident: find incident, service.update(mapped_fields)
      → invoke_ability: Abilities::Invoker.call(ability, mapped_params)
      → trigger_workflow: WorkflowClass.start!(subject, context: mapped_context)
    → Update last_received_at
    → Return 200
```

### Condition Evaluation

```ruby
class WebhookConditionEvaluator
  OPERATORS = {
    "equals" => ->(actual, expected) { actual == expected },
    "not_equals" => ->(actual, expected) { actual != expected },
    "one_of" => ->(actual, expected) { Array(expected).include?(actual) },
    "contains" => ->(actual, expected) { actual.to_s.include?(expected.to_s) },
    "exists" => ->(actual, _) { actual.present? }
  }.freeze

  def self.match?(conditions, payload)
    return true if conditions.blank?
    matcher = conditions["match"] == "any" ? :any? : :all?
    conditions["rules"].send(matcher) do |rule|
      actual = JsonPath.new(rule["path"]).first(payload)
      OPERATORS[rule["operator"]].call(actual, rule["value"] || rule["values"])
    end
  end
end
```

---

## AI Agent Tier

### Progressive Tool Loading

The AI agent gets 3 meta-tools. It discovers, inspects, and invokes abilities on demand — never sees the full catalog.

```ruby
module Ai
  class Agent
    def initialize(workspace, actor)
      @workspace = workspace
      @actor = actor
    end

    def run(prompt, incident: nil)
      RubyLLM.chat(model: FirefightAi.config.default_model) do |chat|
        chat.system(system_prompt)
        chat.with_tools(*meta_tools)
        chat.user(prompt)
      end
    end

    private

    def meta_tools
      [
        FindAbilityTool.new(@workspace, @actor),
        GetAbilitySchemaTool.new(@workspace, @actor),
        InvokeAbilityTool.new(@workspace, @actor)
      ]
    end
  end
end
```

### Meta-Tool Implementations

**`find_ability`** — searches by natural language across `display_name` + `effective_description`. Returns names and descriptions only. Permission-filtered.

**`get_ability_schema`** — returns full `input_schema` for a specific ability by `scope_key`. Loaded from Solid Cache.

**`invoke_ability`** — calls `Abilities::Invoker.call`. If confirmation_required, returns "awaiting confirmation" message. If failed, returns error for agent to recover from.

---

## Credential Management

### Storage

Rails encrypted attributes on `Integration.credentials`. Credential shapes per auth type:

| Auth type | Shape |
|-----------|-------|
| Bearer | `{ type: "bearer", token: "..." }` |
| API key | `{ type: "api_key", key: "...", header: "DD-API-KEY" }` |
| Basic auth | `{ type: "basic", username: "...", password: "..." }` |
| OAuth2 | `{ type: "oauth2", access_token, refresh_token, expires_at, token_url, client_id, client_secret }` |

### Proactive Token Refresh

Solid Queue recurring job checks every 30 minutes for expiring OAuth tokens and refreshes them before expiry. Uses `pg_advisory_lock` on integration ID to prevent refresh races.

```ruby
class CredentialRefreshJob < ApplicationJob
  def perform
    Integration.connected.where(
      "credentials->>'expires_at' < ?", 30.minutes.from_now.iso8601
    ).find_each do |integration|
      integration.with_advisory_lock("credential_refresh_#{integration.id}") do
        Integrations::CredentialRefresher.call(integration)
      end
    end
  end
end
```

---

## Background Jobs

| Job | Schedule | What it does |
|-----|----------|-------------|
| `Integrations::DiscoveryJob` | On integration create, manual refresh | Dispatches to MCP or REST discovery service, upserts abilities, orphan detection |
| `Integrations::HealthCheckJob` | Every 60 min (Solid Queue recurring) | Pings integration via correct connector, updates status |
| `CredentialRefreshJob` | Every 30 min (Solid Queue recurring) | Refreshes expiring OAuth tokens with advisory lock |
| `AuditRetentionJob` | Nightly (Solid Queue recurring) | Deletes invocations older than workspace retention setting |

---

## Relationship to Existing Systems

### Event system

The existing `EventRouter` routes domain events to subscribers. The ability gateway does NOT subscribe to events directly. Workflows subscribe to events and call abilities as step actions.

```
IncidentEvent → ProcessDomainEventJob → EventRouter
  → Webhooks::EventSubscriber (existing — delivers to user-configured outbound webhooks)
  → Workflows::EventSubscriber (future — triggers automation workflows that may invoke abilities)
```

### Adapter pattern

`WorkspaceAdapter` handles the platform the workspace runs on (Slack, Teams). Integrations handle external services (Jira, Datadog, PagerDuty). These are separate systems.

### Existing webhooks

The existing `Webhook` model handles outbound event delivery (Firefight notifies external services). Integration webhook endpoints handle inbound event reception (external services notify Firefight). Different direction, different models, same workspace.

---

## Security

- **Credential encryption**: Rails encrypted attributes at rest. Never in logs, API responses, or audit records.
- **Scope-based RBAC**: Per-integration and per-ability permission checks with wildcard support.
- **Webhook verification**: Inbound webhooks verified via HMAC-SHA256 with per-endpoint signing secret.
- **Workspace isolation**: All queries scoped to workspace. Cross-workspace access impossible by construction.
- **Audit trail**: Every invocation recorded with sanitized input/output, actor, source, duration, and status.
- **Confirmation gates**: Write operations can require human approval. AI and workflows pause until confirmed.

---

## First-Party Integration Catalog

First-party integrations are `Integration` records seeded at workspace onboarding. The workspace authenticates, Firefight stores the credential, and the gateway layer handles discovery, ability creation, and health checks — identical to custom connectors. The difference: Firefight controls `description_override` for better AI tool descriptions.

### Priority

| Integration | Connector | Auth | Slug | Priority |
|-------------|-----------|------|------|----------|
| Datadog | MCP (official) | API key + App key | `datadog` | P0 |
| AWS CloudWatch | MCP (official) | IAM / access key | `aws-cloudwatch` | P0 |
| Grafana | MCP (official) | Service account token | `grafana` | P0 |
| Sentry | MCP (official) | Auth token | `sentry` | P1 |
| New Relic | MCP (community) | API key | `new-relic` | P1 |
| GCP Cloud Logging | MCP (official) | Service account JSON | `gcp-logging` | P1 |
| Jira | REST | OAuth2 / API token | `jira` | P1 |
| Linear | REST | API key | `linear` | P1 |
| PagerDuty | REST | API key | `pagerduty` | P1 |
| GitHub | REST / MCP | OAuth / PAT | `github` | P2 |
| Railway | MCP (official) | API token | `railway` | P2 |
| Fly.io | REST (GraphQL) | Bearer token | `fly` | Backlog |
| Render | REST | API key | `render` | Backlog |

### P0 Details

**Datadog**: MCP official server. Key abilities: `query_metrics`, `get_logs`, `list_monitors`, `get_dashboard`, `list_incidents`. Needs description enrichment — raw tool names are terse. Gotcha: requires both API and Application keys.

**AWS CloudWatch**: MCP official server. Key abilities: `get_metric_statistics`, `filter_log_events`, `describe_alarms`, `get_metric_data`. Needs region scoping in credentials. Competitive differentiator: incident.io's AWS integration is inbound-only (CloudWatch webhook → create incident). They cannot query CloudWatch from their AI. Firefight can.

**Grafana**: MCP official server. Key abilities: `query_datasource`, `get_dashboard`, `list_dashboards`, `get_panel_data`, `create_annotation`. Gotcha: Grafana Cloud vs self-hosted have different base URLs.

### First-Party Seeding

```ruby
module FirstParty
  CATALOG = {
    "datadog" => {
      name: "Datadog",
      connector_type: "mcp",
      connector_url: "https://mcp.datadoghq.com",
      credential_fields: [
        { key: "api_key", label: "API Key", type: "secret" },
        { key: "application_key", label: "Application Key", type: "secret" }
      ],
      description_overrides: {
        "query_metrics" => "Query Datadog metrics for a service, host, or tag over a time range. Use during incidents to check error rates, latency, or resource utilization.",
        "get_logs" => "Search Datadog logs for errors, exceptions, or patterns. Use to investigate what happened during an incident."
      }
    }
    # ... more integrations
  }.freeze

  def self.seed_for_workspace(workspace, slug, credentials)
    catalog_entry = CATALOG.fetch(slug)
    integration = workspace.integrations.create!(
      name: catalog_entry[:name],
      slug: slug,
      connector_type: catalog_entry[:connector_type],
      connector_url: catalog_entry[:connector_url],
      credentials: credentials
    )
    # Discovery runs via after_create_commit callback
    # After discovery, apply description overrides
    ApplyDescriptionOverridesJob.perform_later(integration.id, catalog_entry[:description_overrides])
  end
end
```

---

## Competitive Analysis

| Capability | incident.io | Rootly | Firefight |
|------------|-------------|--------|-----------|
| Exposes self as MCP server | Yes | Yes | Planned (later) |
| AI can query Datadog during incident | Yes (hand-rolled) | No | Yes (via gateway) |
| AI can query CloudWatch during incident | No | No | Yes (via gateway) |
| Workspace can connect custom MCP | No | No | Yes |
| Workspace can enable/disable individual abilities | No | No | Yes |
| Scope-based permission per ability | No | No | Yes |
| Inbound webhooks → auto-create incidents | Yes | Yes | Yes |
| Human-in-the-loop for AI actions | No | No | Yes |
| Workflow automation calling external tools | Yes (hand-rolled) | Yes (hand-rolled) | Yes (via gateway) |
| Adding new integration = code deploy | Yes (their code) | Yes (their code) | No (workspace connects MCP) |

**Sharpest differentiator**: Firefight can query CloudWatch, Grafana, and custom tools from the AI during an incident. Neither competitor can. Adding a new observability tool = workspace connects an MCP. No engineering required.

### Why "I'll just use Claude Code / Cursor" isn't the same thing

Teams will point out that Claude Code and Cursor support MCP and can query the same tools. True — but they're general-purpose AI coding assistants, not incident response agents. The differences compound:

| Capability | Claude Code / Cursor | Firefight AI SRE |
|------------|---------------------|------------------|
| Triggers automatically on incident | No — someone has to open the IDE and type | Yes — fires on incident creation, severity change, or alert |
| Has incident context | No — you paste in the error manually | Yes — timeline, severity, affected services, past incidents, team runbooks |
| Follows your escalation policies | No | Yes — pages the right on-call based on affected service and severity |
| Calls tools with your team's RBAC | No — uses your personal credentials | Yes — workspace scopes, per-ability permissions, confirmation gates |
| Writes to incident timeline | No — results are in your IDE | Yes — findings, actions taken, and decisions are part of the incident record |
| Coordinates multiple agents | No — single chat session | Yes — diagnostics + remediation + comms agents orchestrated via workflows |
| Works at 3 AM without a human | No — someone has to be at the keyboard | Yes — automated response runs immediately, escalates to humans when needed |
| Learns from past incidents | No — each session starts fresh | Yes — long-term memory across incidents in your workspace |
| Audit trail for compliance | No — ephemeral chat history | Yes — every tool call logged with actor, input, output, duration |
| Human-in-the-loop for risky actions | No — executes immediately or not at all | Yes — pauses for approval, resumes on confirmation from Slack |

**The core difference:** Claude Code is a tool you use. Firefight AI SRE is a teammate that runs your incident process. One requires an engineer at the keyboard. The other runs autonomously and brings in engineers only when it needs a human decision.

The people who would use Claude Code instead of paying are not the target customer. The target customer is the team that wants incident response to work automatically during a 3 AM outage without someone babysitting an AI chat window.

### Open Source Strategy

The Ability Gateway (integrations, abilities, invoker, discovery, webhooks, RBAC, workflows) is **open source**. This is the adoption driver — the feature that makes Firefight unique, and the part users need to trust with their credentials.

The AI that uses the gateway is **commercial** (closed source engine):
- AI SRE agent (auto-triggers, multi-agent orchestration)
- Progressive tool loading (meta-tools, semantic search)
- Natural language ability invocation from Slack
- Incident analysis with ability calls
- Long-term memory across incidents
- Postmortem generation

**The line:** Open source users get a complete integration platform with manual invocation, workflows, and webhooks. Paying users get AI that operates autonomously on top of the same platform.

---

## Gotchas

### MCP

- `tools/list` has no pagination. Plan for large tool lists in discovery.
- Not all MCPs implement `initialize`. Wrap in rescue and proceed.
- SSE transport vs HTTP. Build for HTTP first, add SSE later if needed.
- MCP servers can be slow (10-30s). Discovery is always async via Solid Queue.

### Auth

- OAuth token refresh races. Use `pg_advisory_lock` on integration ID before refreshing.
- Plan for Rails encryption key rotation before production.

### Performance

- N+1 on permission checks. Cache aggressively (5-minute TTL).
- Large `input_schema` JSONB objects bloat AI context. Progressive tool loading solves this.

### Slack

- 3-second response limit. Always respond immediately, process async, post result back via `response_url`.
- Slack signature verification is mandatory.

### AI Agent

- Token costs stay flat with progressive tool loading. Without it, costs scale with integration count.
- Tool hallucination: `invoke_ability` must return clear "ability not found" errors for agent recovery.
- Set max iterations on the RubyLLM agent loop to prevent runaway.

---

## Implementation Phases

### Phase 1: Core Gateway + MCP

Build the gateway with MCP support first — this is the differentiator.

**Models:** `Integration`, `Ability`, `Scope`, `Role`, `RoleScope`, `RoleAssignment`, `AbilityInvocation`

**Services:** `Abilities::Invoker`, `PermissionChecker`, `Mcp::Client`, `Mcp::DiscoveryService`, `Connectors::ClientPool`

**Jobs:** `Integrations::DiscoveryJob`, `Integrations::HealthCheckJob`, `CredentialRefreshJob`, `AuditRetentionJob`

**What works:** Workspace connects an MCP server, abilities auto-discovered, invocable from Slack (explicit `/firefight datadog.list_alerts`), full audit trail, RBAC.

### Phase 2: REST Connector + Templates

Add REST connector for services without MCP (Jira, Linear, PagerDuty).

**Services:** `Rest::Client`, `Rest::DiscoveryService`

**What works:** User defines REST API tools with Liquid templates and response mappings. Same invocation interface as MCP abilities.

### Phase 3: Inbound Webhooks

**Models:** `IntegrationWebhookEndpoint`

**Controllers:** `IntegrationWebhooksController`

**Services:** `WebhookConditionEvaluator`, `WebhookActionRouter`

**What works:** External services send webhooks → auto-create/update incidents, invoke abilities, trigger workflows.

### Phase 4: AI Agent + Progressive Tool Loading

**Services:** `Ai::Agent`, `FindAbilityTool`, `GetAbilitySchemaTool`, `InvokeAbilityTool`

**What works:** AI agent discovers and invokes abilities via 3 meta-tools. Natural language commands from Slack. Incident analysis uses integration tools.

### Phase 5: Human-in-the-Loop

Add confirmation flow for sensitive ability invocations.

**What works:** Abilities marked `confirmation_required` pause execution. User approves/rejects from Slack or dashboard. Workflows pause/resume on confirmation.

### Phase 6: First-Party Integrations

Build pre-packaged integrations on the gateway layer.

**Priority:** Datadog (P0) → AWS CloudWatch (P0) → Grafana (P0) → Jira, Linear, PagerDuty (P1)

Each provides: setup wizard with OAuth/credential flow, description overrides, default webhook endpoint configs.

---

## Service Directory

```
app/
  models/
    integration.rb
    ability.rb
    scope.rb
    role.rb
    role_scope.rb
    role_assignment.rb
    ability_invocation.rb
    integration_webhook_endpoint.rb

  services/
    permission_checker.rb
    connectors/
      client_pool.rb                # Solid Cache backed, routes to Mcp:: or Rest::

    mcp/
      client.rb                     # JSON-RPC client
      discovery_service.rb          # tools/list → Ability upserts + orphan detection

    rest/
      client.rb                     # HTTP client with Liquid templates
      discovery_service.rb          # OpenAPI or static definition → Ability upserts

    abilities/
      invoker.rb                    # Permission check → execute → audit log
      errors.rb                     # PermissionDenied, AbilityDisabled, IntegrationDisabled

    webhook/
      condition_evaluator.rb        # Payload condition matching
      action_router.rb              # Route to create_incident / invoke_ability / etc.

    ai/
      agent.rb                      # RubyLLM agentic loop with meta-tools
      find_ability_tool.rb
      get_ability_schema_tool.rb
      invoke_ability_tool.rb

    integrations/
      credential_refresher.rb       # OAuth token refresh with advisory lock

    first_party/
      catalog.rb                    # CATALOG constant + seed_for_workspace
      apply_description_overrides_job.rb

  controllers/
    integration_webhooks_controller.rb  # Inbound webhook receiver

  jobs/
    integrations/
      discovery_job.rb              # Dispatches to Mcp:: or Rest:: discovery
      health_check_job.rb           # Pings integration, updates status
    credential_refresh_job.rb
    audit_retention_job.rb
```
