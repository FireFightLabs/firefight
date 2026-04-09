# Ability Gateway — Implementation

> Incremental build plan for the Ability Gateway.
> Architecture and design rationale: `docs/ABILITY_GATEWAY.md`
> Research predecessor: `docs/ABILITY_GATEWAY_ORIGINAL.md`
> Earlier integration layer design: `docs/INTEGRATION_LAYER.md`

---

## Database Schema

### Entity Relationships

```
Workspace
  ├── has_many :integrations
  ├── has_many :scopes
  ├── has_many :roles
  └── has_many :ability_invocations

Integration
  ├── belongs_to :workspace
  ├── has_many :abilities (dependent: :destroy)
  ├── has_many :integration_webhook_endpoints (dependent: :destroy)
  └── has_one :scope (as: :scopeable, dependent: :destroy)

Ability
  ├── belongs_to :integration
  ├── has_one :workspace (through: :integration)
  ├── has_one :scope (as: :scopeable, dependent: :destroy)
  └── has_many :ability_invocations (dependent: :restrict_with_error)

Scope
  ├── belongs_to :workspace
  ├── belongs_to :scopeable (polymorphic → Integration | Ability)
  ├── has_many :role_scopes
  └── has_many :roles (through: :role_scopes)

Role
  ├── belongs_to :workspace
  ├── has_many :role_scopes
  ├── has_many :scopes (through: :role_scopes)
  ├── has_many :role_assignments
  └── has_many :assignables (through: :role_assignments, polymorphic)

RoleAssignment
  ├── belongs_to :role
  └── belongs_to :assignable (polymorphic → WorkspaceMembership | ApiKey)

AbilityInvocation
  ├── belongs_to :ability
  ├── belongs_to :workspace
  ├── belongs_to :incident (optional)
  └── belongs_to :confirmed_by → WorkspaceMembership (optional)

IntegrationWebhookEndpoint
  └── belongs_to :integration
```

### Migrations

#### `integrations`

```ruby
create_table :integrations do |t|
  t.references :workspace,       null: false, foreign_key: true
  t.string  :name,               null: false
  t.string  :slug,               null: false
  t.string  :connector_type,     null: false, default: "mcp"
  t.string  :connector_url
  t.text    :credentials                        # encrypted via Rails encrypts
  t.string  :status,             null: false, default: "pending"
  t.integer :discovery_generation, null: false, default: 0
  t.integer :health_check_interval_minutes, default: 60
  t.datetime :last_health_check_at
  t.datetime :last_discovered_at
  t.string  :error_message
  t.boolean :enabled,            null: false, default: true
  t.timestamps
end

add_index :integrations, [:workspace_id, :slug], unique: true
add_index :integrations, :status
```

| Column | Type | Notes |
|--------|------|-------|
| `workspace_id` | FK | Owning workspace |
| `name` | string | Display name ("Datadog Production") |
| `slug` | string | URL-safe, unique per workspace, used in scope keys |
| `connector_type` | enum | `mcp` or `rest` |
| `connector_url` | string | MCP server URL or REST base API URL |
| `credentials` | encrypted text | Auth credentials — shape varies by auth type |
| `status` | enum | `pending → discovering → connected → degraded → error → disabled` |
| `discovery_generation` | integer | Incremented per discovery run for orphan detection |
| `health_check_interval_minutes` | integer | Default 60 |
| `enabled` | boolean | Manual enable/disable by workspace admin |

#### `abilities`

```ruby
create_table :abilities do |t|
  t.references :integration,     null: false, foreign_key: true
  t.string  :tool_name,          null: false
  t.string  :display_name,       null: false
  t.text    :description
  t.text    :description_override
  t.jsonb   :input_schema,       null: false, default: {}
  t.jsonb   :tool_config,        null: false, default: {}
  t.boolean :enabled,            null: false, default: false
  t.boolean :confirmation_required, null: false, default: false
  t.integer :discovery_generation, null: false, default: 0
  t.vector  :description_embedding, limit: 1536  # pgvector — for semantic tool discovery
  t.timestamps
end

add_index :abilities, [:integration_id, :tool_name], unique: true
add_index :abilities, :enabled
```

Requires pgvector extension: `enable_extension "vector"` (already planned for code intelligence).

| Column | Type | Notes |
|--------|------|-------|
| `tool_name` | string | Raw name from MCP/REST discovery |
| `display_name` | string | Human-readable name |
| `description` | text | From discovery — used by AI for tool selection |
| `description_override` | text | First-party enrichment — overrides description for AI |
| `input_schema` | jsonb | JSON Schema for expected parameters |
| `tool_config` | jsonb | REST-specific: `{ method, path, payload_template, response_mapping }`. Empty for MCP. |
| `enabled` | boolean | Off by default until workspace enables |
| `confirmation_required` | boolean | Require human approval before executing |
| `discovery_generation` | integer | Stamped during discovery — orphan detection |
| `description_embedding` | vector(1536) | pgvector embedding of `effective_description` — for semantic search in `FindAbilityTool` |

**Key methods:**
- `scope_key` → `"ability:#{integration.slug}.#{tool_name}"`
- `effective_description` → `description_override.presence || description`
- `generate_embedding!` → embeds `effective_description` via cheap embedding model, stores in `description_embedding`

#### `scopes`

```ruby
create_table :scopes do |t|
  t.references :workspace,       null: false, foreign_key: true
  t.string  :key,                null: false
  t.text    :description
  t.references :scopeable,       polymorphic: true, null: false
  t.timestamps
end

add_index :scopes, [:workspace_id, :key], unique: true
```

| Column | Type | Notes |
|--------|------|-------|
| `key` | string | `"integration:datadog"` or `"ability:datadog.list_alerts"` |
| `scopeable` | polymorphic | Points to `Integration` or `Ability` |

Auto-created when integrations and abilities are created. Supports wildcard matching: `ability:datadog.*` matches `ability:datadog.list_alerts`.

#### `roles`

```ruby
create_table :roles do |t|
  t.references :workspace,       null: false, foreign_key: true
  t.string  :name,               null: false
  t.text    :description
  t.timestamps
end

add_index :roles, [:workspace_id, :name], unique: true
```

#### `role_scopes`

```ruby
create_table :role_scopes do |t|
  t.references :role,            null: false, foreign_key: true
  t.references :scope,           null: false, foreign_key: true
  t.timestamps
end

add_index :role_scopes, [:role_id, :scope_id], unique: true
```

#### `role_assignments`

```ruby
create_table :role_assignments do |t|
  t.references :role,            null: false, foreign_key: true
  t.references :assignable,      polymorphic: true, null: false
  t.timestamps
end

add_index :role_assignments, [:role_id, :assignable_type, :assignable_id],
          unique: true, name: "idx_role_assignments_uniqueness"
```

Assignable types: `WorkspaceMembership`, `ApiKey`.

#### `ability_invocations`

```ruby
create_table :ability_invocations do |t|
  t.references :ability,         null: false, foreign_key: true
  t.references :workspace,       null: false, foreign_key: true
  t.references :incident,        null: true, foreign_key: true
  t.string  :source,             null: false
  t.string  :invoked_by_type
  t.bigint  :invoked_by_id
  t.jsonb   :input,              null: false, default: {}
  t.jsonb   :output,             default: {}
  t.string  :status,             null: false, default: "pending"
  t.integer :duration_ms
  t.integer :token_count                         # AI agent sessions: total tokens used
  t.text    :error_message
  t.references :confirmed_by,    null: true, foreign_key: { to_table: :workspace_memberships }
  t.datetime :confirmed_at
  t.timestamps
end

add_index :ability_invocations, [:workspace_id, :created_at]
add_index :ability_invocations, [:ability_id, :created_at]
add_index :ability_invocations, :status
```

| Column | Type | Notes |
|--------|------|-------|
| `source` | string | `slack`, `ai_agent`, `workflow`, `dashboard` |
| `invoked_by` | polymorphic | Actor who triggered (WorkspaceMembership, SolidWorkflow::Step, etc.) |
| `input` | jsonb | Sanitized — sensitive keys redacted before write |
| `output` | jsonb | Sanitized — sensitive keys redacted before write |
| `status` | enum | `pending → awaiting_confirmation → confirmed → executing → succeeded / failed / rejected` |
| `duration_ms` | integer | Execution time in milliseconds |
| `token_count` | integer | Total tokens consumed (AI agent sessions only) |
| `confirmed_by` | FK | User who approved, if confirmation_required |

#### `integration_webhook_endpoints`

```ruby
create_table :integration_webhook_endpoints do |t|
  t.references :integration,     null: false, foreign_key: true
  t.string  :name,               null: false
  t.string  :slug,               null: false
  t.string  :secret,             null: false
  t.boolean :active,             null: false, default: true
  t.jsonb   :conditions,         null: false, default: {}
  t.string  :action_type,        null: false
  t.jsonb   :action_config,      null: false, default: {}
  t.datetime :last_received_at
  t.timestamps
end

add_index :integration_webhook_endpoints, :slug, unique: true
```

| Column | Type | Notes |
|--------|------|-------|
| `slug` | string | Generates URL: `POST /webhooks/integrations/:slug` |
| `secret` | string | HMAC-SHA256 signing secret, auto-generated |
| `conditions` | jsonb | `{ rules: [{ path, operator, value }], match: "all"/"any" }` |
| `action_type` | enum | `create_incident`, `update_incident`, `invoke_ability`, `trigger_workflow` |
| `action_config` | jsonb | Liquid field mappings, ability scope_key, workflow class, etc. |

---

## Implementation Steps

Each step is a deployable, testable increment. Step 3 is the keystone — once the invoker works, everything else plugs into it.

---

### Step 1: Models + Migrations + RBAC

**Builds:** Data foundation. All 8 tables, models, associations, validations, permission system.

**Migrations:** All 8 listed above.

**Models:**

| File | Responsibility |
|------|---------------|
| `app/models/integration.rb` | `belongs_to :workspace`, `has_many :abilities`. Validates slug format `/\A[a-z0-9\-]+\z/`, unique per workspace. Enum status. `encrypts :credentials`. `scope_key` → `"integration:#{slug}"`. `after_create :create_integration_scope!` |
| `app/models/ability.rb` | `belongs_to :integration`. Validates tool_name unique per integration. `scope_key` → `"ability:#{integration.slug}.#{tool_name}"`. `effective_description` → override or description. `after_create :create_ability_scope!` |
| `app/models/scope.rb` | Polymorphic `scopeable`. `self.wildcard_match?(user_key, required_key)` — `"ability:datadog.*"` matches `"ability:datadog.list_alerts"` |
| `app/models/role.rb` | `belongs_to :workspace`, `has_many :scopes` through `role_scopes` |
| `app/models/role_scope.rb` | Join table |
| `app/models/role_assignment.rb` | Polymorphic `assignable`. `after_create_commit` / `after_destroy_commit` → invalidate permission cache |
| `app/models/ability_invocation.rb` | Audit record. Enum status: `pending, awaiting_confirmation, confirmed, executing, succeeded, failed, rejected` |
| `app/models/integration_webhook_endpoint.rb` | `belongs_to :integration`. Model only, controller comes in Step 7 |

**Services:**

| File | Responsibility |
|------|---------------|
| `app/services/permission_checker.rb` | `can?(scope_key)`, `can_invoke?(ability)`. Loads actor's scopes via roles, caches 5 min in Solid Cache. Wildcard matching. |

**Tests:**
- All model validations and associations
- Scope `wildcard_match?` (exact, wildcard, non-match)
- PermissionChecker (`can?`, `can_invoke?`, cache hit, cache invalidation on role change)
- Integration auto-creates scope on create
- Ability auto-creates scope on create

**Result:** Schema exists, RBAC works. No external calls.

---

### Step 2: MCP Connector + Discovery

**Builds on:** Step 1 models.

**What it adds:** MCP client (JSON-RPC 2.0), discovery service with generation-based orphan detection, async discovery job, connector client pool.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/services/mcp/client.rb` | JSON-RPC client. `initialize_session!` (lazy), `list_tools` → array of tool hashes, `call_tool(name, args)` → result hash. Auth via bearer or API key header. Timeout: 10s. |
| `app/services/mcp/discovery_service.rb` | 1) Set status `discovering`. 2) Increment `discovery_generation`. 3) `client.list_tools`. 4) Upsert each as Ability with current generation. 5) Create Scope for new abilities. 6) Generate `description_embedding` for new/changed abilities (batch embed via cheap model). 7) Delete orphans (wrong generation). 8) Invalidate cached schemas. 9) Set status `connected`. 10) On error → status `error`. |
| `app/services/connectors/client_pool.rb` | `self.get(integration)` — Solid Cache backed, 10 min TTL. Returns `Mcp::Client` or `Rest::Client` based on `connector_type`. `self.invalidate(integration)`. |
| `app/jobs/integrations/discovery_job.rb` | Queue: `:integrations`. Finds integration, dispatches to `Mcp::DiscoveryService` (or `Rest::DiscoveryService` later). Logs errors. |

**Model changes:**
- `Integration`: `after_create_commit :enqueue_discovery` → `Integrations::DiscoveryJob.perform_later(id)`
- `Integration`: `mcp?` / `rest?` convenience methods from enum

**MCP JSON-RPC format:**

```ruby
# Request
{ jsonrpc: "2.0", id: SecureRandom.uuid, method: "tools/list", params: {} }

# Response
{ "result" => { "tools" => [{ "name" => "list_alerts", "description" => "...", "inputSchema" => {...} }] } }
```

**Tests:**
- `Mcp::Client` — stub HTTP, verify JSON-RPC request format, parse response
- `Mcp::DiscoveryService` — new abilities created, existing updated, orphans deleted, generation counter increments, status transitions
- Integration test: `Integration.create!(connector_type: "mcp", ...)` → DiscoveryJob runs inline → abilities exist in DB

**Result:** Create MCP integration → abilities auto-discovered. Not invocable yet.

---

### Step 3: Invocation Layer + Audit

**Builds on:** Step 2 abilities exist in DB.

**What it adds:** The invoker — permission check, execute via connector, write audit record. This is the single entry point that all consumers use.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/services/abilities/invoker.rb` | `self.call(ability, arguments, actor, source:, incident: nil)`. 1) Permission check. 2) Validate enabled + connected. 3) Create AbilityInvocation (pending). 4) Get client from pool. 5) `client.call_tool`. 6) Sanitize output. 7) Update invocation (succeeded/failed). |
| `app/services/abilities/errors.rb` | `PermissionDenied`, `AbilityDisabled`, `IntegrationDisabled` — all inherit from `Abilities::Error` |

**Credential masking:**

```ruby
SENSITIVE_KEYS = %w[token password secret key authorization api_key bearer].freeze

def sanitize(params)
  return params unless params.is_a?(Hash)
  params.each_with_object({}) do |(k, v), h|
    h[k] = SENSITIVE_KEYS.any? { |s| k.to_s.downcase.include?(s) } ? "[REDACTED]" : v
  end
end
```

Applied to both `input` and `output` before writing AbilityInvocation.

**Invoker interface:**

```ruby
# Any consumer calls this — same interface everywhere
invocation = Abilities::Invoker.call(
  ability,
  { status: "triggered" },         # arguments
  current_membership,               # actor
  source: "slack",                  # slack | ai_agent | workflow | dashboard
  incident: @incident               # optional
)

invocation.succeeded?   # => true
invocation.output       # => { "alerts" => [...] }
invocation.duration_ms  # => 342
```

**Tests:**
- Success path: invocation created, output recorded, duration tracked
- Permission denied: raises `Abilities::PermissionDenied`, no invocation created
- Ability disabled: raises `Abilities::AbilityDisabled`
- Integration disconnected: raises `Abilities::IntegrationDisabled`
- Connector error: invocation status `failed`, error_message recorded
- Credential masking: sensitive keys redacted in stored input/output

**Result:** `Abilities::Invoker.call(ability, args, actor, source: "test")` works. Full RBAC + audit trail.

---

### Step 4: Slack Explicit Invocation

**Builds on:** Step 3 invoker.

**What it adds:** Slash command handler for explicit ability invocation from Slack.

**Files:**

| File | Change |
|------|--------|
| `app/models/identifiers.rb` | Add `SUBCOMMAND_INVOKE = "invoke"` |
| `app/services/command_dispatcher.rb` | Route `invoke` subcommand to handler |
| `app/handlers/slack/invoke_ability_handler.rb` | New handler: parse ability key + args, find ability, call invoker, format response |

**Command format:** `/firefight invoke datadog.list_alerts status=triggered`

**Handler flow:**

```ruby
def self.execute(command)
  parts = command.text.split(" ", 2)  # after subcommand is stripped
  ability_key = parts[0]               # "datadog.list_alerts"
  args_string = parts[1]               # "status=triggered"

  integration_slug, tool_name = ability_key.split(".", 2)
  ability = Ability.joins(:integration)
    .where(integrations: { workspace: command.workspace, slug: integration_slug })
    .find_by!(tool_name: tool_name, enabled: true)

  arguments = parse_key_value_args(args_string)

  invocation = Abilities::Invoker.call(
    ability, arguments, command.membership, source: "slack", incident: command.incident
  )

  format_slack_response(invocation)
rescue ActiveRecord::RecordNotFound
  ephemeral("Unknown ability `#{ability_key}`. Run `/firefight abilities` to see available abilities.")
rescue Abilities::PermissionDenied
  ephemeral("You don't have permission to use `#{ability_key}`.")
end
```

**Argument parsing:** `"status=triggered priority=high"` → `{ "status" => "triggered", "priority" => "high" }`

**Tests:**
- Handler tests with Command objects
- Argument parsing (key=value pairs, empty args, quoted values)
- Permission denied → ephemeral error
- Unknown ability → ephemeral error
- Successful invocation → formatted Slack response

**Result:** Users can run `/firefight invoke datadog.list_alerts status=triggered` from Slack.

---

### Step 5: Background Jobs

**Builds on:** Steps 2 + 3.

**What it adds:** Recurring maintenance — health checks, credential refresh, audit retention.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/jobs/integrations/health_check_job.rb` | Recurring. For each `connected`/`degraded` integration: lightweight connector ping. Update status to `connected` or `degraded`. |
| `app/jobs/credential_refresh_job.rb` | Recurring. Find integrations with OAuth `expires_at` within 30 min. Advisory lock per integration. Refresh token. Update credentials. |
| `app/jobs/audit_retention_job.rb` | Recurring. Delete `ability_invocations` older than retention setting (default 30 days). |
| `app/services/integrations/credential_refresher.rb` | OAuth token refresh logic. Acquires `pg_advisory_lock` to prevent races. Calls token URL, updates encrypted credentials. |

**Solid Queue config (`config/recurring.yml`):**

```yaml
production:
  credential_refresh:
    class: CredentialRefreshJob
    schedule: every 30 minutes

  integration_health_check:
    class: Integrations::HealthCheckJob
    schedule: every 60 minutes

  audit_retention:
    class: AuditRetentionJob
    schedule: every day at midnight
```

**CredentialRefresher details:**
- Only processes `type: "oauth2"` credentials
- Checks `expires_at < 30.minutes.from_now`
- Uses `integration.with_advisory_lock("credential_refresh_#{id}")` to prevent concurrent refresh
- On success: updates `access_token`, `expires_at`, optionally `refresh_token`
- On failure: sets integration status to `degraded`

**Tests:**
- CredentialRefresher: token refreshed, race condition (second job skips), failure → degraded
- HealthCheck: connected stays connected, failed ping → degraded, recovered → connected
- AuditRetention: old records deleted, recent records kept

**Result:** Integrations stay healthy automatically. OAuth tokens refresh before expiry. Audit logs don't grow unbounded.

---

### Step 6: REST Connector

**Builds on:** Steps 2 + 3 (same pattern as MCP, different transport).

**What it adds:** REST client with Liquid payload templates and JSONPath response mapping. REST discovery from OpenAPI specs or static definitions.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/services/rest/client.rb` | 1) Render `tool_config.payload_template` with Liquid + input params. 2) Build URL: `connector_url + tool_config.path`. 3) Set auth headers from credentials. 4) HTTP request. 5) Parse response. 6) Apply `response_mapping` (JSONPath). 7) Return mapped output. |
| `app/services/rest/discovery_service.rb` | Parse OpenAPI spec or read static YAML definition → create Abilities. Same generation-based orphan detection as MCP. |

**REST tool_config example:**

```ruby
{
  "method" => "POST",
  "path" => "/rest/api/3/issue",
  "headers" => { "X-Custom" => "value" },
  "payload_template" => {
    "fields" => {
      "project" => { "key" => "{{ project_key }}" },
      "summary" => "{{ summary }}",
      "issuetype" => { "name" => "{{ issue_type | default: 'Task' }}" }
    }
  },
  "response_mapping" => {
    "id" => "$.id",
    "key" => "$.key",
    "url" => "$.self"
  }
}
```

**Auth injection (from `integration.credentials`):**

| `credentials.type` | Header |
|--------------------|--------|
| `bearer` | `Authorization: Bearer #{token}` |
| `api_key` | `#{credentials.header}: #{credentials.key}` |
| `basic` | `Authorization: Basic #{Base64.strict_encode64("#{username}:#{password}")}` |
| `oauth2` | `Authorization: Bearer #{access_token}` |

**Changes to existing code:**
- `Integrations::DiscoveryJob`: dispatch to `Rest::DiscoveryService` when `connector_type == "rest"`
- `Connectors::ClientPool`: return `Rest::Client` for `rest` type
- `Abilities::Invoker`: unchanged — already connector-agnostic via `ClientPool`

**Tests:**
- Rest::Client: Liquid template rendering, HTTP request with correct headers, JSONPath response mapping
- Liquid edge cases: missing variables, default filters, nested objects
- REST discovery from OpenAPI spec
- Auth injection for each credential type

**Result:** REST API integrations work. Jira, Linear, PagerDuty connectable as REST with custom tool definitions.

---

### Step 7: Inbound Webhooks

**Builds on:** Step 3 invoker + Step 1 IntegrationWebhookEndpoint model.

**What it adds:** HTTP endpoint that receives webhooks from external services, evaluates conditions, and routes to actions.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/controllers/integration_webhooks_controller.rb` | `POST /webhooks/integrations/:slug`. Find endpoint, verify signature, parse payload, evaluate conditions, route action, return 200. |
| `app/services/webhooks/condition_evaluator.rb` | `self.match?(conditions, payload)`. JSONPath extraction + operator matching (`equals`, `not_equals`, `one_of`, `contains`, `exists`). `all`/`any` rule matching. |
| `app/services/webhooks/action_router.rb` | `self.route(endpoint, payload)`. Dispatches to action handler by `action_type`. Renders Liquid field mappings against payload. |

**Route:** `post '/webhooks/integrations/:slug', to: 'integration_webhooks#receive'`

**Controller flow:**

```ruby
def receive
  endpoint = IntegrationWebhookEndpoint.find_by!(slug: params[:slug], active: true)
  verify_signature!(endpoint, request)
  payload = JSON.parse(request.body.read)

  if Webhooks::ConditionEvaluator.match?(endpoint.conditions, payload)
    Webhooks::ActionRouter.route(endpoint, payload)
  end

  endpoint.touch(:last_received_at)
  head :ok
rescue ActiveRecord::RecordNotFound
  head :not_found
rescue Webhooks::SignatureVerificationFailed
  head :unauthorized
end
```

**Action routing:**

| `action_type` | What happens |
|---------------|-------------|
| `create_incident` | Render `action_config.field_mappings` with Liquid against payload → `IncidentLifecycleService.create(...)` |
| `update_incident` | Find incident via `action_config.incident_lookup` → `IncidentLifecycleService.update(...)` |
| `invoke_ability` | Find ability by `action_config.ability_scope_key` → `Abilities::Invoker.call(...)` |
| `trigger_workflow` | Find workflow class from `action_config.workflow_class` → `WorkflowClass.start!(...)` |

**Condition operators:**

| Operator | Behavior |
|----------|---------|
| `equals` | `actual == expected` |
| `not_equals` | `actual != expected` |
| `one_of` | `Array(expected).include?(actual)` |
| `contains` | `actual.to_s.include?(expected.to_s)` |
| `exists` | `actual.present?` |

**Tests:**
- Controller: valid signature → 200, invalid → 401, unknown slug → 404
- ConditionEvaluator: each operator, `all` matching, `any` matching, empty conditions (pass-through)
- ActionRouter: each action type with Liquid rendering
- Integration test: curl POST webhook → incident created in DB

**Result:** External services (Datadog, PagerDuty, custom) send webhooks → Firefight auto-creates/updates incidents or invokes abilities.

---

### Step 8: Human-in-the-Loop

**Builds on:** Step 3 invoker.

**What it adds:** Confirmation flow for sensitive abilities. Invoker pauses, notifies user, resumes on approval.

**Changes to `Abilities::Invoker`:**

```ruby
# In call():
if @ability.confirmation_required?
  invocation.update!(status: "awaiting_confirmation")
  notify_for_confirmation(invocation)
  return invocation  # caller handles async
end

# New class methods:
def self.confirm(invocation, confirmed_by:)
  invocation.update!(
    status: "confirmed",
    confirmed_by: confirmed_by,
    confirmed_at: Time.current
  )
  # Re-execute with original params
  new(invocation.ability, invocation.raw_input, confirmed_by, source: invocation.source)
    .execute!(invocation)
end

def self.reject(invocation, rejected_by:)
  invocation.update!(
    status: "rejected",
    confirmed_by: rejected_by,
    confirmed_at: Time.current
  )
  invocation
end
```

**Slack notification:**
- Posts to incident channel (or DMs actor): confirmation required message with ability name, params summary
- Block action buttons: Approve / Reject
- Action IDs: `Identifiers::CONFIRM_ABILITY_INVOCATION`, `Identifiers::REJECT_ABILITY_INVOCATION`

**New handlers:**

| File | Responsibility |
|------|---------------|
| `app/handlers/slack/confirm_ability_handler.rb` | Finds AbilityInvocation from action value, calls `Invoker.confirm`, posts result |
| `app/handlers/slack/reject_ability_handler.rb` | Finds AbilityInvocation from action value, calls `Invoker.reject`, posts confirmation |

**Workflow integration:**

When a SolidWorkflow step calls an ability that requires confirmation:

```ruby
def create_jira_ticket(workflow:, step:, input:)
  invocation = Abilities::Invoker.call(ability, args, step, source: "workflow", incident: workflow.subject)

  if invocation.awaiting_confirmation?
    # Store invocation ID in step checkpoint for resume
    step.update!(checkpoint: { invocation_id: invocation.id })
    raise SolidWorkflow::StepPaused, "Awaiting confirmation"
  end

  { ticket_id: invocation.output["id"] }
end
```

On confirmation, the workflow step resumes with the invocation result.

**Tests:**
- Invoker: confirmation_required ability → status `awaiting_confirmation`, no execution
- Invoker.confirm: executes ability, updates invocation
- Invoker.reject: marks rejected, no execution
- Slack handlers: approve/reject via block actions
- Workflow: step pauses on confirmation, resumes on approve

**Result:** Sensitive abilities (deploy, restart, create ticket) require explicit human approval before executing.

---

### Step 9: AI Agent + Progressive Tool Loading

**Builds on:** Step 3 invoker.

**What it adds:** AI agent with 3 meta-tools for progressive ability discovery and invocation.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/services/ai/agent.rb` | RubyLLM agentic loop. System prompt + 3 meta-tools. Max 15 iterations. |
| `app/services/ai/find_ability_tool.rb` | **pgvector semantic search** on `description_embedding` (primary) with ILIKE fallback for exact name matches. Embed query, find nearest neighbors. Workspace + connected + enabled filter. Permission-filtered. Returns max 10 results: `[{ name, description }]`. |
| `app/services/ai/get_ability_schema_tool.rb` | Parse `slug.tool_name`, find ability, return `{ name, description, input_schema }`. Served from Solid Cache. |
| `app/services/ai/invoke_ability_tool.rb` | Parse scope_key, find ability, call `Abilities::Invoker.call(source: "ai_agent")`. On confirmation_required: return message. On error: return error for agent recovery. Writes `token_count` to invocation after AI session completes. |

**Agent system prompt:**

```
You are Firefight's AI assistant. You help engineers investigate and resolve incidents.

You have access to meta-tools to discover and invoke abilities connected by this team:
- Use find_ability to search for relevant abilities by description
- Use get_ability_schema to understand a tool's parameters before invoking
- Use invoke_ability to actually call a tool

Always search for abilities before trying to invoke. Never guess ability names.
Be concise. Engineers are usually under pressure during incidents.
```

**Progressive loading flow:**

```
Agent receives: "check if Datadog has any critical alerts"
  → find_ability(query: "datadog alerts") → [{ name: "datadog.list_monitors", description: "..." }]
  → get_ability_schema(ability_name: "datadog.list_monitors") → { input_schema: { status: { type: "string" } } }
  → invoke_ability(ability_name: "datadog.list_monitors", arguments: { status: "Alert" }) → { monitors: [...] }
  → Agent formats response for user
```

Base context cost: 3 small tool schemas. Stays flat regardless of how many integrations exist.

**Tests:**
- FindAbilityTool: search returns matches, respects permissions, filters disabled/disconnected
- GetAbilitySchemaTool: returns schema, not found error
- InvokeAbilityTool: success, permission denied, confirmation required, error recovery
- Agent integration test with stubbed LLM: tool call sequence works end-to-end

**Result:** AI agent discovers and invokes abilities during incident analysis. Natural language from Slack.

---

### Step 10: First-Party Integrations

**Builds on:** Steps 2 + 6 (MCP + REST connectors).

**What it adds:** Pre-packaged integrations with setup wizards, description overrides, and default webhook endpoints.

**Files:**

| File | Responsibility |
|------|---------------|
| `app/services/first_party/catalog.rb` | `CATALOG` hash constant — name, connector_type, connector_url, credential_fields, description_overrides, default_webhook_endpoints per integration. `seed_for_workspace(workspace, slug, credentials)`. |
| `app/jobs/first_party/apply_description_overrides_job.rb` | After discovery completes, applies `description_override` to abilities matching tool_name keys. |

**Catalog entry structure:**

```ruby
{
  name: "Datadog",
  connector_type: "mcp",
  connector_url: "https://mcp.datadoghq.com",
  credential_fields: [
    { key: "api_key", label: "API Key", type: "secret" },
    { key: "application_key", label: "Application Key", type: "secret" }
  ],
  description_overrides: {
    "query_metrics" => "Query Datadog metrics for a service, host, or tag. Use during incidents to check error rates, latency, or resource utilization.",
    "get_logs" => "Search Datadog logs for errors, exceptions, or patterns. Use to investigate what happened during an incident."
  },
  default_webhook_endpoints: [
    {
      name: "Datadog Alert",
      action_type: "create_incident",
      conditions: { rules: [{ path: "$.alertType", operator: "equals", value: "error" }], match: "all" },
      action_config: { field_mappings: { name: "{{ title }}", summary: "{{ body }}", source: "datadog" } }
    }
  ]
}
```

**Seeding flow:**
1. `FirstParty.seed_for_workspace(workspace, "datadog", { api_key: "...", application_key: "..." })`
2. Creates `Integration` record → triggers `DiscoveryJob` (auto via callback)
3. After discovery: `ApplyDescriptionOverridesJob` enriches ability descriptions
4. Creates default `IntegrationWebhookEndpoint` records

**Priority:**

| Priority | Integration | Connector |
|----------|-------------|-----------|
| P0 | Datadog | MCP |
| P0 | AWS CloudWatch | MCP |
| P0 | Grafana | MCP |
| P1 | Sentry | MCP |
| P1 | Jira | REST |
| P1 | Linear | REST |
| P1 | PagerDuty | REST |
| P2 | GitHub | REST / MCP |
| P2 | Railway | MCP |

**Tests:**
- Catalog seeding creates integration + triggers discovery
- Description overrides applied after discovery
- Default webhook endpoints created
- End-to-end: seed Datadog → discovery → abilities with enriched descriptions → invoke

**Result:** First-party integrations available with one-click setup. AI descriptions tuned for accurate tool selection.

---

### Step 11: Observability + Usage Metrics

**Builds on:** Step 3 (ability_invocations exist with per-call data).

**What it adds:** Aggregated usage metrics, OpenTelemetry instrumentation, Grafana dashboards, cost tracking.

**The data already exists.** `ability_invocations` has `ability_id`, `source`, `status`, `duration_ms`, `token_count`, `created_at`. Metrics are queries over this table, not a new data store.

#### Usage Metrics Service

| File | Responsibility |
|------|---------------|
| `app/models/ability_usage_stats.rb` | PORO (same pattern as `DashboardStats`). Queries `ability_invocations` for aggregated metrics. Cached in Solid Cache per workspace. |

**Metrics computed:**

| Metric | Query | Cache TTL |
|--------|-------|-----------|
| Invocations per ability (24h / 7d / 30d) | `GROUP BY ability_id, COUNT(*)` | 5 min |
| Invocations by source (slack / ai / workflow / dashboard) | `GROUP BY source, COUNT(*)` | 5 min |
| Success / failure rate per ability | `GROUP BY ability_id, status` | 5 min |
| P50 / P95 latency per ability | `PERCENTILE_CONT(0.5 / 0.95) WITHIN GROUP (ORDER BY duration_ms)` | 5 min |
| Total token usage per workspace (24h / 7d / 30d) | `SUM(token_count) WHERE source = 'ai_agent'` | 5 min |
| Most-used abilities (top 10) | `GROUP BY ability_id ORDER BY COUNT(*) DESC LIMIT 10` | 5 min |
| Active integrations per workspace | `COUNT(DISTINCT integration_id) WHERE status = 'succeeded'` | 5 min |
| Error rate by integration | `GROUP BY integration_id, failed count / total count` | 5 min |

**Dashboard UI:**
- Settings → Integrations page: per-integration stats (invocation count, success rate, avg latency)
- Per-ability detail: invocation history, latency chart, error rate
- Workspace-level: total invocations, token usage, cost estimate, most-used abilities

#### OpenTelemetry Instrumentation

| File | Responsibility |
|------|---------------|
| `config/initializers/opentelemetry.rb` | Configure OTEL SDK, export to Grafana/Loki via OTLP |
| Changes to `app/services/abilities/invoker.rb` | Wrap execution in OTEL span with attributes |

**Invoker spans:**

```ruby
def call
  OpenTelemetry.tracer("firefight.abilities").in_span(
    "ability.invoke",
    attributes: {
      "ability.name" => @ability.scope_key,
      "ability.integration" => @ability.integration.slug,
      "ability.connector_type" => @ability.integration.connector_type,
      "ability.source" => @source,
      "workspace.id" => @ability.integration.workspace_id
    }
  ) do |span|
    # ... existing invocation logic ...
    span.set_attribute("ability.status", invocation.status)
    span.set_attribute("ability.duration_ms", invocation.duration_ms)
    span.set_attribute("ability.token_count", invocation.token_count) if invocation.token_count
  end
end
```

**Spans created:**
- `ability.invoke` — full invocation lifecycle
- `ability.permission_check` — RBAC check duration
- `ability.connector.call` — actual connector HTTP call (MCP or REST)
- `ability.discovery` — discovery service runs

All flow to Grafana via OTLP exporter → existing Loki/Grafana observability stack.

#### Grafana Dashboards

Pre-built dashboards (provisioned via `infra/obs-server/config/`):

| Dashboard | Panels |
|-----------|--------|
| **Gateway Overview** | Total invocations (24h), success rate, P95 latency, top abilities, invocations by source |
| **Integration Health** | Per-integration status, error rate, latency, last health check |
| **AI Agent Usage** | Token consumption (24h/7d/30d), invocations per session, cost estimate, agent error rate |
| **Alerts** | Error rate spike (>10% failures in 5 min), integration degraded, token budget exceeded |

#### Grafana Alerting

| Alert | Condition | Channel |
|-------|-----------|---------|
| High error rate | >10% ability invocations failing in 5 min window | Slack + email |
| Integration degraded | Integration status changed to `degraded` or `error` | Slack |
| Token budget warning | AI token usage >80% of workspace monthly budget | Slack |
| Latency spike | P95 latency >5s for any ability over 15 min | Slack |

#### Cost Tracking

For AI agent sessions:
- `token_count` on `AbilityInvocation` tracks per-invocation tokens
- `AbilityUsageStats` aggregates to workspace-level daily/weekly/monthly totals
- Workspace can set a `monthly_token_budget` — alert when approaching
- Dashboard shows: tokens used, estimated cost (configurable price per token), trend

**Tests:**
- `AbilityUsageStats` query tests (mock invocation data, verify aggregations)
- OTEL span creation tests (verify attributes set correctly)
- Cache invalidation tests (new invocations update cached stats)

**Result:** Full visibility into what's being used, how it's performing, and what it costs. Grafana dashboards + alerts from day one.

---

## Verification

After each step, run `bin/ci` (rubocop, brakeman, tests). Additionally:

| Step | Manual verification |
|------|-------------------|
| 1 | `rails console` — create models, test permissions |
| 2 | Create MCP integration → verify abilities with embeddings in DB |
| 3 | `Abilities::Invoker.call(...)` from console → verify invocation record |
| 4 | `/firefight invoke datadog.list_alerts` from Slack |
| 5 | Check Solid Queue dashboard for recurring jobs running |
| 6 | Create REST integration with Liquid template → invoke |
| 7 | `curl -X POST /webhooks/integrations/:slug` → verify incident created |
| 8 | Invoke confirmation_required ability → verify Slack notification → approve |
| 9 | Natural language query from Slack → AI discovers via vector search + invokes ability |
| 10 | Add Datadog from settings → one-click setup → abilities ready |
| 11 | Check Grafana dashboards → invocation counts, latency, token usage visible |
