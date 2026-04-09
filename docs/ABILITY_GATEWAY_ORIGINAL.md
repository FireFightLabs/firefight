# Firefight Ability Gateway — Full Implementation Guide

> Rails 8 · Solid Queue · Solid Cache · PostgreSQL · RubyLLM  
> Last updated: April 2026

---

## Table of Contents

1. [What We're Building](#1-what-were-building)
2. [Prior Art & Sources](#2-prior-art--sources)
3. [Key Ideas Stolen From Existing Implementations](#3-key-ideas-stolen-from-existing-implementations)
4. [Data Model](#4-data-model)
5. [Permission & Scope System](#5-permission--scope-system)
6. [Connector Layer & Discovery](#6-connector-layer--discovery)
7. [Credential Management](#7-credential-management)
8. [Invocation Layer](#8-invocation-layer)
9. [Slack Integration](#9-slack-integration)
10. [AI Agent Tier](#10-ai-agent-tier)
11. [Background Jobs (Solid Queue)](#11-background-jobs-solid-queue)
12. [Audit Logging](#12-audit-logging)
13. [Things to Watch Out For](#13-things-to-watch-out-for)
14. [First-Party Integrations](#14-first-party-integrations)
15. [Competitive Analysis — incident.io & Rootly](#15-competitive-analysis--incidentio--rootly)

---

## 1. What We're Building

A **multi-tenant Ability Gateway** embedded inside Firefight (Rails 8). It:

- Lets tenants connect external services ("integrations") via MCP or REST connectors
- Auto-discovers tools from those integrations and surfaces them as "abilities"
- Enforces a flexible scope-based permission system across all invocations
- Exposes abilities via Slack slash commands (free tier: explicit, paid tier: AI agent)
- Uses Solid Queue for async discovery, credential refresh, and log retention jobs

**MCP is one connector type, not the system.** The gateway speaks "ability" at every layer above the connector. Whether an ability came from a Datadog MCP server or a Render REST adapter is an implementation detail the rest of the system never needs to know.

```
Ability Gateway             ← the whole system
  └── Connectors
        ├── Mcp::Client     ← JSON-RPC over HTTP, for integrations that support MCP
        └── Rest::Client    ← HTTP REST, for integrations that don't (Fly, Render, etc.)
```

This is **not** a standalone gateway like the OSS projects below — it's a domain layer inside Firefight, deeply integrated with tenants, billing, and Slack.

**Critical architectural decision: first-party integrations run on the same gateway layer as custom tenant integrations.** Firefight's own Datadog integration is just an `Integration` record pointing at Datadog's connector URL — same model, same discovery, same ability store, same permission system as anything a tenant brings themselves. There is no separate internal integration layer. Every improvement to the gateway benefits first-party integrations automatically, and first-party integrations harden the gateway before it opens to custom tenant connectors.

**Build order:**
1. Build the gateway layer (sections 4–12)
2. Build first-party integrations on top of it (section 14)
3. Open to tenant custom connectors (MCP and REST)
4. AI SRE reads from the unified ability store — first-party and custom alike

---

## 2. Prior Art & Sources

These were read in full before this document was written. Steal ideas, not code.

| Project | What it is | Link | Why it's relevant |
|---|---|---|---|
| **agentic-community/mcp-gateway-registry** | Enterprise MCP gateway with RBAC, OAuth, dynamic tool discovery, audit logging | https://github.com/agentic-community/mcp-gateway-registry | Most complete reference. Has per-tool scope access control, session multiplexing, generation-based discovery, token refresh service |
| **IBM ContextForge** | Open-source MCP + REST + gRPC gateway with admin UI | https://github.com/IBM/mcp-context-forge | Good on virtual server model, transport normalisation, TOON compression idea |
| **fastmcp-gateway** (Ultrathink) | MCP gateway with 3 meta-tools for progressive discovery | https://ultrathinksolutions.com/the-signal/mcp-gateway/ | **Critical** for AI tier — explains why dumping all schemas is wrong |
| **e2b-dev/awesome-mcp-gateways** | Curated list of all MCP gateway projects | https://github.com/e2b-dev/awesome-mcp-gateways | Good landscape survey |
| **MCP Mesh** | Open-source MCP control plane with RBAC, OAuth 2.1, encrypted token vault, multi-tenant | Listed in awesome-mcp-gateways | Multi-tenant org scoping matches our model exactly |
| **Traefik Hub MCP Gateway** | Kubernetes MCP gateway with per-tool policy expressions | https://doc.traefik.io/traefik-hub/mcp-gateway/guides/getting-started | Good on policy expression language for tool-level access |
| **STOA API Gateway Comparison** | Comparison of API gateways with MCP support in 2026 | https://docs.gostoa.dev/blog/open-source-api-gateway-2026 | Good on why MCP needs native support, not plugin bolted onto HTTP proxy |
| **MCP Protocol Spec** | Official MCP spec — tools/list, tools/call, JSON-RPC | https://modelcontextprotocol.io/introduction | Ground truth for what MCP actually does |

---

## 3. Key Ideas Stolen From Existing Implementations

### 3.1 Cache Ability Schemas — Don't Hit Connectors Live

**Source:** agentic-community registry — 60-second cached aggregation for `tools/list`

Calling `tools/list` on an MCP server (or an equivalent discovery call on a REST connector) is a network call. Every Slack command would trigger it at invocation time if you don't cache. Instead: fetch on discovery, store the full `input_schema` JSONB on the `Ability` model, and serve from Postgres. Use Solid Cache for in-memory hot path.

```ruby
# Solid Cache wrapping the DB read
def ability_schema(ability_id)
  Rails.cache.fetch("ability:schema:#{ability_id}", expires_in: 5.minutes) do
    Ability.find(ability_id).input_schema
  end
end
```

Invalidate on rediscovery. Never call `tools/list` at invocation time.

---

### 3.2 Generation-Based Orphan Detection on Rediscovery

**Source:** agentic-community registry — generation counters for sync

When you re-discover abilities for an integration (nightly job or manual refresh), how do you know which abilities were removed? Diffing name lists is fragile. Use a generation counter:

```ruby
# On each discovery run
integration.increment!(:discovery_generation)

# Upsert each discovered tool, stamping current generation
ability.update!(discovery_generation: integration.discovery_generation)

# After upsert loop — delete anything not in this generation
integration.abilities.where.not(
  discovery_generation: integration.discovery_generation
).destroy_all
```

This also handles renames cleanly — old name is orphaned, new name is created.

---

### 3.3 Progressive Tool Loading for the AI Tier

**Source:** fastmcp-gateway (Ultrathink) — https://ultrathinksolutions.com/the-signal/mcp-gateway/

**This is the most architecturally important idea.**

Dumping all enabled ability schemas into the LLM context is wrong. A tenant with 5 integrations × 20 tools each = 100 tool schemas in every request. Token cost spikes, wrong tools get picked, context fills before the user's message.

Instead, give the AI **3 meta-tools** and let it load schemas on demand:

```ruby
# The 3 meta-tools exposed to RubyLLM for the AI agent
META_TOOLS = [
  {
    name: "find_ability",
    description: "Search available abilities by natural language description. Returns names and descriptions only, not full schemas.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "What you want to do" }
      }
    }
  },
  {
    name: "get_ability_schema",
    description: "Get the full input schema for a specific ability before invoking it.",
    input_schema: {
      type: "object",
      properties: {
        ability_name: { type: "string" }
      }
    }
  },
  {
    name: "invoke_ability",
    description: "Invoke an ability by name with arguments.",
    input_schema: {
      type: "object",
      properties: {
        ability_name: { type: "string" },
        arguments: { type: "object" }
      }
    }
  }
]
```

The agent loop: `find_ability` → `get_ability_schema` → `invoke_ability`. Base context cost = 3 small schemas regardless of how many integrations the tenant has.

Store **pg_search-compatible descriptions** on `Ability` so `find_ability` can do full-text search across `display_name` + `description` per tenant.

---

### 3.4 Credential Masking in Audit Logs

**Source:** agentic-community registry — automatic credential masking with TTL retention

Never log raw credentials in `AbilityInvocation`. Build the sanitiser into the writer:

```ruby
SENSITIVE_KEYS = %w[token password secret key authorization api_key bearer].freeze

def sanitize_params(params)
  return params unless params.is_a?(Hash)
  params.transform_values.with_object({}) do |(k, v), h|
    h[k] = SENSITIVE_KEYS.any? { |s| k.to_s.downcase.include?(s) } ? "[REDACTED]" : v
  end
end
```

Apply to both `input` and `output` before writing `AbilityInvocation`.

---

### 3.5 Token Refresh as a Background Job

**Source:** agentic-community registry — `start_token_refresher.sh` dedicated process

OAuth tokens expire. Don't discover this at invocation time. Run a Solid Queue recurring job that checks every integration's credential expiry and refreshes proactively:

```ruby
# Runs every 30 minutes via Solid Queue
class CredentialRefreshJob < ApplicationJob
  def perform
    Integration.connected.where(
      "credentials->>'expires_at' < ?",
      30.minutes.from_now.iso8601
    ).find_each do |integration|
      Integrations::CredentialRefresher.call(integration)
    end
  end
end
```

Store `expires_at` inside the encrypted `credentials` JSONB so the query above works.

---

### 3.6 Integration Health States Beyond Binary

**Source:** agentic-community registry — `connected | error | discovering | security_pending`

Don't use a boolean `connected` field. Use a status enum:

| Status | Meaning |
|---|---|
| `pending` | Just added, not yet connected |
| `discovering` | Solid Queue discovery job is running |
| `connected` | Discovery succeeded, abilities are live |
| `degraded` | Last health check failed but was previously connected |
| `error` | Discovery failed or credentials invalid |
| `disabled` | Tenant manually disabled |

The `discovering` state is especially important for UX — tenant admins can see the job is running and know abilities will appear shortly.

---

### 3.7 Virtual Server / Tool Namespacing

**Source:** agentic-community registry — tool aliasing to resolve naming conflicts; Traefik Hub MCP Gateway — policy expressions per tool

Two integrations will have identically named tools. `list-alerts` appears in both Datadog and PagerDuty connectors. The canonical ability name must be `integration_slug.tool_name` throughout:

```ruby
# Ability#scope_key — used everywhere: scopes, invocations, AI tool names
def scope_key
  "#{integration.slug}.#{tool_name}"
end

# Never use raw tool_name as the identifier. Always scope_key.
```

This is also the value used in scope strings: `ability:datadog.list_alerts`.

---

### 3.8 Connection Pooling Per Connector

**Source:** agentic-community registry — one client session maps to N backend MCP sessions

Don't open a new connector connection per tool call. Maintain a cached client per integration per tenant, reused across invocations within the cache window. Works for both MCP (session state) and REST (connection reuse). See `Connectors::ClientPool` in section 6.

```ruby
# Connectors::ClientPool — Solid Cache backed, connector-type aware
def self.get(integration)
  key = "connector:client:#{integration.tenant_id}:#{integration.id}"
  Rails.cache.fetch(key, expires_in: 10.minutes) do
    case integration.connector_type
    when "mcp"  then Mcp::Client.new(integration.connector_url, integration.credentials)
    when "rest" then Rest::Client.new(integration.connector_url, integration.credentials)
    end
  end
end
```

---

### 3.9 TTL-Based Audit Log Retention

**Source:** agentic-community registry — 7-day default with configurable TTL

Add `audit_retention_days` to `Tenant` (default 7). Nightly Solid Queue job purges old invocations:

```ruby
class AuditRetentionJob < ApplicationJob
  def perform
    Tenant.find_each do |tenant|
      cutoff = tenant.audit_retention_days.days.ago
      tenant.ability_invocations.where("created_at < ?", cutoff).delete_all
    end
  end
end
```

---

## 4. Data Model

### 4.1 Migrations

```ruby
# integrations
create_table :integrations do |t|
  t.references :tenant, null: false, foreign_key: true
  t.string :name,             null: false
  t.string :slug,             null: false  # url-safe, used in scope keys
  t.string :connector_type,   null: false, default: "mcp"  # "mcp" | "rest"
  t.string :connector_url                  # MCP server URL for mcp type; base API URL for rest type
  t.jsonb  :credentials,      null: false, default: {}     # encrypted at column level
  t.string :status,           null: false, default: "pending"
  t.integer :discovery_generation, null: false, default: 0
  t.integer :health_check_interval_minutes, default: 60
  t.datetime :last_health_check_at
  t.datetime :last_discovered_at
  t.boolean :enabled,         null: false, default: true
  t.timestamps
end

add_index :integrations, [:tenant_id, :slug], unique: true
add_index :integrations, :status

# abilities
create_table :abilities do |t|
  t.references :integration, null: false, foreign_key: true
  t.string :tool_name,        null: false  # raw MCP tool name
  t.string :display_name,     null: false
  t.text   :description
  t.jsonb  :input_schema,     null: false, default: {}
  t.boolean :enabled,         null: false, default: false  # off by default until tenant enables
  t.integer :discovery_generation, null: false, default: 0
  t.timestamps
end

add_index :abilities, [:integration_id, :tool_name], unique: true
add_index :abilities, :enabled

# scopes
create_table :scopes do |t|
  t.references :tenant, null: false, foreign_key: true
  t.string :key,         null: false  # "integration:datadog" | "ability:datadog.list_alerts"
  t.string :description
  t.references :scopeable, polymorphic: true  # -> Integration or Ability
  t.timestamps
end

add_index :scopes, [:tenant_id, :key], unique: true

# roles
create_table :roles do |t|
  t.references :tenant, null: false, foreign_key: true
  t.string :name, null: false
  t.text :description
  t.timestamps
end

add_index :roles, [:tenant_id, :name], unique: true

# role_scopes (join)
create_table :role_scopes do |t|
  t.references :role,  null: false, foreign_key: true
  t.references :scope, null: false, foreign_key: true
  t.timestamps
end

add_index :role_scopes, [:role_id, :scope_id], unique: true

# role_assignments — attach roles to anything
create_table :role_assignments do |t|
  t.references :role, null: false, foreign_key: true
  t.references :assignable, polymorphic: true  # SlackUser, ApiKey, etc.
  t.timestamps
end

add_index :role_assignments, [:role_id, :assignable_type, :assignable_id], unique: true

# ability_invocations (audit log)
create_table :ability_invocations do |t|
  t.references :ability, null: false, foreign_key: true
  t.references :tenant,  null: false, foreign_key: true
  t.string :source,      null: false  # "slack" | "api" | "ai_agent"
  t.string :invoked_by                # slack_user_id or api_key_id
  t.jsonb  :input,       null: false, default: {}
  t.jsonb  :output,      default: {}
  t.string :status,      null: false, default: "pending"  # pending | success | error
  t.integer :duration_ms
  t.text   :error_message
  t.timestamps
end

add_index :ability_invocations, [:tenant_id, :created_at]
add_index :ability_invocations, [:ability_id, :created_at]
```

### 4.2 Models

```ruby
class Integration < ApplicationRecord
  belongs_to :tenant
  has_many :abilities, dependent: :destroy
  has_one :scope, as: :scopeable, dependent: :destroy

  enum :status, {
    pending: "pending",
    discovering: "discovering",
    connected: "connected",
    degraded: "degraded",
    error: "error",
    disabled: "disabled"
  }

  enum :connector_type, { mcp: "mcp", rest: "rest" }

  validates :slug, presence: true, uniqueness: { scope: :tenant_id },
                   format: { with: /\A[a-z0-9\-]+\z/ }

  encrypts :credentials  # Rails 7.2 encrypted attributes

  after_create :create_scope!
  after_create_commit :enqueue_discovery

  def scope_key = "integration:#{slug}"

  private

  def create_scope!
    Scope.create!(
      tenant: tenant,
      key: scope_key,
      description: "Access to #{name} integration",
      scopeable: self
    )
  end

  # Routes to the correct discovery job based on connector type.
  # The job resolves to Mcp::DiscoveryService or Rest::DiscoveryService internally.
  # Everything above this layer speaks "ability" — connector type is irrelevant.
  def enqueue_discovery
    Integrations::DiscoveryJob.perform_later(id)
  end
end

class Ability < ApplicationRecord
  belongs_to :integration
  has_one :tenant, through: :integration
  has_one :scope, as: :scopeable, dependent: :destroy

  scope :enabled, -> { where(enabled: true) }

  after_create :create_scope!

  def scope_key = "ability:#{integration.slug}.#{tool_name}"

  def create_scope!
    Scope.create!(
      tenant: integration.tenant,
      key: scope_key,
      description: description,
      scopeable: self
    )
  end
end

class Scope < ApplicationRecord
  belongs_to :tenant
  belongs_to :scopeable, polymorphic: true
  has_many :role_scopes, dependent: :destroy
  has_many :roles, through: :role_scopes

  validates :key, presence: true, uniqueness: { scope: :tenant_id }

  def self.wildcard_match?(user_scope_key, required_key)
    return true if user_scope_key == required_key
    # "ability:datadog.*" matches "ability:datadog.list_alerts"
    if user_scope_key.ends_with?(".*")
      prefix = user_scope_key.delete_suffix(".*")
      required_key.start_with?(prefix)
    else
      false
    end
  end
end

class Role < ApplicationRecord
  belongs_to :tenant
  has_many :role_scopes, dependent: :destroy
  has_many :scopes, through: :role_scopes
  has_many :role_assignments, dependent: :destroy
end
```

---

## 5. Permission & Scope System

### 5.1 Why Custom (Not Pundit/CanCanCan)

- **Pundit** — policy objects per resource. Wrong mental model for string scopes.
- **CanCanCan** — aging DSL, no concept of scope strings or wildcards.
- **Rolify** — polymorphic roles but no wildcard matching, would need significant extension.

Decision: **build our own**. It's 4 tables and ~30 lines of Ruby. No leaky abstractions.

### 5.2 PermissionChecker

```ruby
class PermissionChecker
  def initialize(actor)
    @actor = actor
  end

  # actor = SlackUser, ApiKey, etc — anything with role_assignments
  def can?(required_scope_key)
    user_scope_keys.any? do |user_key|
      Scope.wildcard_match?(user_key, required_scope_key)
    end
  end

  def can_invoke?(ability)
    can?("integration:#{ability.integration.slug}") &&
      can?("ability:#{ability.scope_key.split('ability:').last}")
  end

  private

  def user_scope_keys
    @user_scope_keys ||= Rails.cache.fetch(
      "permission:#{@actor.class.name}:#{@actor.id}",
      expires_in: 5.minutes
    ) do
      @actor.roles
            .flat_map(&:scopes)
            .map(&:key)
            .uniq
    end
  end
end
```

### 5.3 Usage

```ruby
checker = PermissionChecker.new(slack_user)
checker.can?("integration:datadog")              # single scope check
checker.can?("ability:datadog.list_alerts")      # ability scope check
checker.can_invoke?(ability)                     # both checks at once
```

### 5.4 Cache Invalidation

Invalidate permission cache when roles change:

```ruby
class RoleAssignment < ApplicationRecord
  after_create  :invalidate_actor_permission_cache
  after_destroy :invalidate_actor_permission_cache

  private

  def invalidate_actor_permission_cache
    Rails.cache.delete("permission:#{assignable.class.name}:#{assignable.id}")
  end
end
```

---

## 6. Connector Layer & Discovery

The connector layer is the only place in the codebase that knows or cares about connector type. Everything above it — the ability store, permission system, invocation layer, AI agent — operates on abilities, not on MCP or REST.

```
Integrations::DiscoveryJob        ← dispatches to correct service
  ├── Mcp::DiscoveryService       ← calls tools/list via JSON-RPC
  └── Rest::DiscoveryService      ← reads OpenAPI spec or static definition

Abilities::Invoker                ← calls correct client
  ├── Mcp::Client                 ← tools/call via JSON-RPC
  └── Rest::Client                ← HTTP request per ability definition
```

The dispatcher job is the seam:

```ruby
class Integrations::DiscoveryJob < ApplicationJob
  queue_as :integrations

  def perform(integration_id)
    integration = Integration.find(integration_id)

    service = case integration.connector_type
              when "mcp"  then Mcp::DiscoveryService.new(integration)
              when "rest" then Rest::DiscoveryService.new(integration)
              else raise "Unknown connector type: #{integration.connector_type}"
              end

    service.call
  rescue => e
    Rails.logger.error("Discovery failed for integration #{integration_id}: #{e.message}")
  end
end
```

The same pattern applies in `Abilities::Invoker` — it calls `Mcp::Client` or `Rest::Client` based on `ability.integration.connector_type`. Neither the invoker nor anything upstream branches on connector type for any other reason.

### 6.1 MCP Protocol Basics

MCP uses JSON-RPC 2.0. The two calls you need:

```
POST {mcp_url}
Content-Type: application/json

# Initialize session
{ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {} } }

# List tools
{ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }
```

`tools/list` returns:
```json
{
  "result": {
    "tools": [
      {
        "name": "list_alerts",
        "description": "List active Datadog alerts",
        "inputSchema": {
          "type": "object",
          "properties": {
            "status": { "type": "string", "enum": ["triggered", "resolved"] }
          }
        }
      }
    ]
  }
}
```

MCP spec reference: https://modelcontextprotocol.io/introduction

### 6.2 Mcp::Client

```ruby
module Mcp
  class Client
    def initialize(connector_url, credentials = {})
      @connector_url = connector_url
      @credentials = credentials
      @session_initialized = false
    end

    def list_tools
      initialize_session! unless @session_initialized
      response = post(method: "tools/list")
      response.dig("result", "tools") || []
    end

    def call_tool(tool_name, arguments = {})
      initialize_session! unless @session_initialized
      post(
        method: "tools/call",
        params: { name: tool_name, arguments: arguments }
      )
    end

    private

    def initialize_session!
      post(
        method: "initialize",
        params: {
          protocolVersion: "2024-11-05",
          capabilities: {},
          clientInfo: { name: "firefight", version: "1.0" }
        }
      )
      @session_initialized = true
    end

    def post(method:, params: {})
      response = HTTP
        .auth(auth_header)
        .timeout(10)
        .post(@connector_url, json: {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: method,
          params: params
        })

      raise Mcp::Error, "MCP request failed: #{response.status}" unless response.status.success?

      body = response.parse(:json)
      raise Mcp::Error, body["error"]["message"] if body["error"]
      body
    end

    def auth_header
      case @credentials["type"]
      when "bearer" then "Bearer #{@credentials["token"]}"
      when "api_key" then "Api-Key #{@credentials["key"]}"
      end
    end
  end
end
```

### 6.3 Mcp::DiscoveryService

```ruby
module Mcp
  class DiscoveryService
    def initialize(integration)
      @integration = integration
    end

    def call
      @integration.update!(status: :discovering)
      current_gen = @integration.discovery_generation + 1
      @integration.update!(discovery_generation: current_gen)

      tools = client.list_tools

      tools.each do |tool|
        upsert_ability(tool, current_gen)
      end

      # Orphan detection — remove tools not seen in this discovery run
      @integration.abilities
                  .where.not(discovery_generation: current_gen)
                  .each do |orphan|
                    orphan.scope&.destroy
                    orphan.destroy
                  end

      @integration.update!(
        status: :connected,
        last_discovered_at: Time.current
      )

    rescue Mcp::Error, HTTP::Error => e
      @integration.update!(status: :error)
      raise
    end

    private

    def client
      @client ||= Mcp::Client.new(
        @integration.connector_url,
        @integration.credentials
      )
    end

    def upsert_ability(tool, generation)
      ability = @integration.abilities.find_or_initialize_by(
        tool_name: tool["name"]
      )

      ability.assign_attributes(
        display_name: tool["name"].humanize,
        description: tool["description"],
        input_schema: tool["inputSchema"] || {},
        discovery_generation: generation
      )

      # Only create scope if this is a new ability
      is_new = ability.new_record?
      ability.save!
      ability.create_scope! if is_new

      # Invalidate cached schema
      Rails.cache.delete("ability:schema:#{ability.id}")
    end
  end
end
```

---

## 7. Credential Management

### 7.1 Rails Encrypted Attributes

Use Rails 7.2 built-in encrypted attributes. No third-party gem needed:

```ruby
# integration.rb
encrypts :credentials  # encrypts the JSONB column at rest

# Credential shape per connector type:
# OAuth2:
{
  "type" => "oauth2",
  "access_token" => "...",
  "refresh_token" => "...",
  "expires_at" => "2026-04-04T12:00:00Z",
  "token_url" => "https://api.datadog.com/oauth2/token",
  "client_id" => "...",
  "client_secret" => "..."
}

# API key:
{
  "type" => "api_key",
  "key" => "...",
  "header" => "DD-API-KEY"  # which header to inject
}

# Bearer:
{
  "type" => "bearer",
  "token" => "..."
}
```

### 7.2 Credential Refresher

```ruby
module Integrations
  class CredentialRefresher
    def self.call(integration)
      new(integration).call
    end

    def initialize(integration)
      @integration = integration
    end

    def call
      creds = @integration.credentials
      return unless creds["type"] == "oauth2"
      return unless needs_refresh?(creds)

      response = HTTP.post(creds["token_url"], form: {
        grant_type: "refresh_token",
        refresh_token: creds["refresh_token"],
        client_id: creds["client_id"],
        client_secret: creds["client_secret"]
      })

      raise "Token refresh failed: #{response.status}" unless response.status.success?

      data = response.parse(:json)

      @integration.update!(credentials: creds.merge(
        "access_token" => data["access_token"],
        "expires_at" => data["expires_in"].seconds.from_now.iso8601,
        "refresh_token" => data.fetch("refresh_token", creds["refresh_token"])
      ))
    end

    private

    def needs_refresh?(creds)
      return false unless creds["expires_at"]
      Time.parse(creds["expires_at"]) < 30.minutes.from_now
    end
  end
end
```

---

## 8. Invocation Layer

### 8.1 Abilities::Invoker

```ruby
module Abilities
  class Invoker
    SENSITIVE_KEYS = %w[token password secret key authorization api_key bearer].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(ability, arguments, actor, source:)
      @ability = ability
      @arguments = arguments
      @actor = actor
      @source = source
    end

    def call
      check_permissions!
      check_ability_enabled!

      invocation = AbilityInvocation.create!(
        ability: @ability,
        tenant: @ability.integration.tenant,
        source: @source,
        invoked_by: @actor.id.to_s,
        input: sanitize(@arguments),
        status: "pending"
      )

      started_at = Time.current

      begin
        client = Connectors::ClientPool.get(@ability.integration)
        result = client.call_tool(@ability.tool_name, @arguments)

        invocation.update!(
          output: sanitize(result),
          status: "success",
          duration_ms: ((Time.current - started_at) * 1000).to_i
        )

        result
      rescue => e
        invocation.update!(
          status: "error",
          error_message: e.message,
          duration_ms: ((Time.current - started_at) * 1000).to_i
        )
        raise
      end
    end

    private

    def check_permissions!
      checker = PermissionChecker.new(@actor)
      raise Abilities::PermissionDenied unless checker.can_invoke?(@ability)
    end

    def check_ability_enabled!
      raise Abilities::AbilityDisabled unless @ability.enabled?
      raise Abilities::IntegrationDisabled unless @ability.integration.connected?
    end

    def sanitize(params)
      return params unless params.is_a?(Hash)
      params.transform_values.with_object({}) do |(k, v), h|
        h[k] = SENSITIVE_KEYS.any? { |s| k.to_s.downcase.include?(s) } ? "[REDACTED]" : v
      end
    end
  end
end
```

### 8.2 Mcp::ClientPool

```ruby
module Mcp
  class ClientPool
    def self.get(integration)
      key = "mcp:client:#{integration.tenant_id}:#{integration.id}"
      # Sessions are cached in Solid Cache for 10 minutes
      # A new client is created if the session expires or is evicted
      Rails.cache.fetch(key, expires_in: 10.minutes) do
        Mcp::Client.new(integration.mcp_url, integration.credentials)
      end
    end

    def self.invalidate(integration)
      Rails.cache.delete("mcp:client:#{integration.tenant_id}:#{integration.id}")
    end
  end
end
```

---

## 9. Slack Integration

### 9.1 Command Parser

```ruby
module Slack
  class CommandHandler
    def initialize(tenant, slack_user, text)
      @tenant = tenant
      @slack_user = slack_user
      @text = text.strip
    end

    def handle
      if explicit_invocation?
        handle_explicit
      elsif @tenant.ai_tier?
        handle_ai
      else
        { text: "Upgrade to use natural language commands. Try `/firefight help` to see available commands." }
      end
    end

    private

    # Explicit: "/firefight datadog.list_alerts status=triggered"
    def explicit_invocation?
      @text.match?(/\A[\w\-]+\.[\w\-]+/)
    end

    def handle_explicit
      parts = @text.split(" ", 2)
      ability_key = parts[0]    # "datadog.list_alerts"
      args_string = parts[1]    # "status=triggered"

      ability = Ability
        .joins(:integration)
        .where(integrations: { tenant: @tenant })
        .find_by!(
          "concat(integrations.slug, '.', abilities.tool_name) = ?",
          ability_key
        )

      arguments = parse_args(args_string)

      result = Abilities::Invoker.call(
        ability, arguments, @slack_user, source: "slack"
      )

      Slack::ResponseFormatter.format(result)
    rescue ActiveRecord::RecordNotFound
      { text: "Unknown ability `#{ability_key}`. Try `/firefight help`." }
    rescue Abilities::PermissionDenied
      { text: "You don't have permission to use `#{ability_key}`." }
    end

    def handle_ai
      Ai::Agent.new(@tenant, @slack_user).run(@text)
    end

    def parse_args(args_string)
      return {} if args_string.blank?
      args_string.scan(/(\w+)=(\S+)/).to_h
    end
  end
end
```

### 9.2 Slack Controller

```ruby
class SlackCommandsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_slack_signature

  def handle
    # Respond immediately (Slack requires < 3s)
    # Then process async and post result back
    response_url = params[:response_url]
    tenant = Tenant.find_by_slack_team_id!(params[:team_id])

    Slack::ProcessCommandJob.perform_later(
      tenant_id: tenant.id,
      user_id: params[:user_id],
      text: params[:text],
      response_url: response_url
    )

    render json: { text: "Processing..." }
  end

  private

  def verify_slack_signature
    # Verify X-Slack-Signature header
    # https://api.slack.com/authentication/verifying-requests-from-slack
  end
end
```

---

## 10. AI Agent Tier

### 10.1 Agent with Progressive Tool Loading

```ruby
module Ai
  class Agent
    def initialize(tenant, actor)
      @tenant = tenant
      @actor = actor
    end

    def run(prompt)
      RubyLLM.chat(model: "claude-sonnet-4-5") do |chat|
        chat.system(system_prompt)
        chat.with_tools(*meta_tools)
        chat.user(prompt)
        # RubyLLM handles the agentic loop — keeps calling tools until done
      end
    end

    private

    def meta_tools
      [
        FindAbilityTool.new(@tenant, @actor),
        GetAbilitySchemaTool.new(@tenant, @actor),
        InvokeAbilityTool.new(@tenant, @actor)
      ]
    end

    def system_prompt
      <<~PROMPT
        You are Firefight's AI assistant. You help engineers investigate and resolve incidents.
        
        You have access to meta-tools to discover and invoke abilities connected by this team:
        - Use find_ability to search for relevant abilities by description
        - Use get_ability_schema to understand a tool's parameters before invoking
        - Use invoke_ability to actually call a tool
        
        Always search for abilities before trying to invoke. Never guess ability names.
        Be concise. Engineers are usually under pressure during incidents.
      PROMPT
    end
  end
end
```

### 10.2 Meta-Tool Implementations

```ruby
module Ai
  class FindAbilityTool
    def initialize(tenant, actor)
      @tenant = tenant
      @actor = actor
    end

    def name = "find_ability"
    def description = "Search available abilities by what you want to do. Returns names and descriptions only."

    def call(query:)
      checker = PermissionChecker.new(@actor)

      Ability
        .joins(:integration)
        .where(integrations: { tenant: @tenant, status: "connected" })
        .where(enabled: true)
        .where(
          "abilities.display_name ILIKE :q OR abilities.description ILIKE :q",
          q: "%#{query}%"
        )
        .limit(10)
        .map do |ability|
          next unless checker.can_invoke?(ability)
          {
            name: ability.scope_key.split("ability:").last,
            description: ability.description
          }
        end.compact
    end
  end

  class GetAbilitySchemaTool
    def initialize(tenant, actor)
      @tenant = tenant
      @actor = actor
    end

    def name = "get_ability_schema"
    def description = "Get the full input schema for a specific ability before invoking it."

    def call(ability_name:)
      ability = find_ability!(ability_name)
      {
        name: ability_name,
        description: ability.description,
        input_schema: ability.input_schema
      }
    end

    private

    def find_ability!(name)
      integration_slug, tool_name = name.split(".", 2)
      Ability
        .joins(:integration)
        .find_by!(
          integrations: { tenant: @tenant, slug: integration_slug },
          tool_name: tool_name,
          enabled: true
        )
    end
  end

  class InvokeAbilityTool
    def initialize(tenant, actor)
      @tenant = tenant
      @actor = actor
    end

    def name = "invoke_ability"
    def description = "Invoke an ability with the given arguments."

    def call(ability_name:, arguments: {})
      integration_slug, tool_name = ability_name.split(".", 2)
      ability = Ability
        .joins(:integration)
        .find_by!(
          integrations: { tenant: @tenant, slug: integration_slug },
          tool_name: tool_name
        )

      Abilities::Invoker.call(
        ability, arguments, @actor, source: "ai_agent"
      )
    end
  end
end
```

---

## 11. Background Jobs (Solid Queue)

### 11.1 Job Map

| Job | Trigger | What it does |
|---|---|---|
| `Integrations::DiscoveryJob` | After integration created, manual refresh | Dispatches to `Mcp::DiscoveryService` or `Rest::DiscoveryService`, upserts abilities, orphan detection |
| `Integrations::HealthCheckJob` | Solid Queue recurring, every 60min | Pings integration via correct connector, updates status to degraded/connected |
| `CredentialRefreshJob` | Solid Queue recurring, every 30min | Finds expiring OAuth tokens, refreshes them |
| `AuditRetentionJob` | Solid Queue recurring, nightly | Deletes invocations older than tenant's retention setting |

### 11.2 Discovery Job

```ruby
# Routes to the right discovery service based on connector_type.
# See section 6 for the full dispatcher implementation.
class Integrations::DiscoveryJob < ApplicationJob
  queue_as :integrations

  def perform(integration_id)
    integration = Integration.find(integration_id)
    service = integration.mcp? ? Mcp::DiscoveryService : Rest::DiscoveryService
    service.new(integration).call
  rescue => e
    Rails.logger.error("Discovery failed for integration #{integration_id}: #{e.message}")
  end
end
```

### 11.3 Solid Queue Config (config/recurring.yml)

```yaml
# config/recurring.yml
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

---

## 12. Audit Logging

Every invocation — whether from Slack, the API, or the AI agent — writes to `AbilityInvocation`. This gives you:

- Full audit trail for compliance
- Debugging data when an ability fails
- Usage analytics per ability, per integration, per source

Key fields:
- `source` — where it came from (`slack | api | ai_agent`)
- `invoked_by` — the actor ID (Slack user ID, API key ID, etc.)
- `input` — sanitized arguments (credentials stripped)
- `output` — sanitized result
- `duration_ms` — for latency tracking
- `status` — `pending | success | error`

Use `created_at` indexing for time-range queries and the nightly retention job.

---

## 13. Things to Watch Out For

### MCP Connector Gotchas

- **`tools/list` has no pagination.** If an MCP server returns 200+ tools, you get them all at once. Plan for this in the discovery service — don't assume small lists.
- **Not all MCPs implement `initialize`.** Some older/minimal MCPs skip the handshake. Wrap in rescue and proceed.
- **SSE transport vs HTTP.** The MCP spec supports both Server-Sent Events and Streamable HTTP. Most hosted MCPs use HTTP. Build for HTTP first, add SSE support later if needed.
- **MCP servers can be slow.** Discovery can take 10-30s for remote MCPs. This is why it's async in a Solid Queue job and never in-request.

### Auth Gotchas

- **OAuth token refresh races.** If two jobs try to refresh the same token simultaneously, you'll make two refresh calls and one will be invalid. Use `with_advisory_lock` (pg_advisory_lock) on the integration ID before refreshing.
- **Credentials column needs encryption key rotation plan.** Plan for how you'll rotate Rails encryption keys without downtime before you go to production.

### Performance

- **N+1 on permission checks.** `PermissionChecker` loads all roles and scopes for an actor. Cache aggressively (see section 5.2). The 5-minute TTL is a good starting point.
- **Ability schema JSONB.** Large `input_schema` objects are fine in Postgres JSONB but watch out for abilities with deeply nested schemas — they bloat the context window when fed to the AI. Store as-is but trim before feeding to the AI.

### Slack

- **3-second response limit.** Slack will show an error if your endpoint doesn't respond in 3 seconds. Always respond immediately with "Processing..." and use a Solid Queue job + `response_url` to post the actual result asynchronously.
- **Slack signature verification is mandatory.** Verify `X-Slack-Signature` using HMAC-SHA256 before processing any command. Without this, anyone can POST to your endpoint.

### AI Agent

- **Token costs.** Progressive tool loading (section 3.3) keeps costs flat. Without it, a tenant with 10 integrations × 20 tools = 200 schemas per request. At GPT/Claude pricing this adds up fast.
- **Tool hallucination.** The AI will sometimes invoke `find_ability` with a plausible but wrong name. The `InvokeAbilityTool` should raise a clear error ("ability not found") and let the agent recover, not crash the loop.
- **Agent loop runaway.** Set a max iterations limit on the RubyLLM agent loop (check RubyLLM docs for `max_iterations`). Without it, a confused agent can loop indefinitely and rack up token costs.

---

## 14. First-Party Integrations

### 14.1 Strategy

First-party integrations are Firefight-managed `Integration` records seeded at tenant onboarding. The tenant authenticates (API key, OAuth, IAM role), Firefight stores the credential, and the gateway layer takes it from there — discovery, ability creation, health checks, all identical to a custom tenant connector.

The key difference from custom connectors: Firefight controls the `description` and `display_name` on discovered abilities for first-party integrations. Raw tool descriptions from MCP servers or REST specs are often terse and written for developers, not for an AI reasoning about when to use them during an incident. For first-party integrations, override these in a post-discovery enrichment step so the AI tier works well out of the box.

Add `description_override` to the `Ability` model:

```ruby
# migration
add_column :abilities, :description_override, :text

# ability.rb — effective_description used everywhere the AI reads descriptions
def effective_description
  description_override.presence || description
end
```

### 14.2 Integration Inventory

| Integration | Connector | Auth Type | Slug | Priority | Source |
|---|---|---|---|---|---|
| Datadog | MCP (official) | API key + App key | `datadog` | P0 | https://github.com/DataDog/datadog-mcp-server |
| AWS CloudWatch | MCP (official) | IAM role or access key | `aws-cloudwatch` | P0 | https://github.com/aws/aws-mcp-servers |
| Grafana | MCP (official) | API token | `grafana` | P0 | https://github.com/grafana/mcp-grafana |
| Sentry | MCP (official) | Auth token | `sentry` | P1 | https://github.com/getsentry/sentry-mcp |
| New Relic | MCP (community) | API key | `new-relic` | P1 | https://github.com/newrelic/newrelic-mcp-server |
| GCP Cloud Logging | MCP (official) | Service account JSON | `gcp-logging` | P1 | https://github.com/googleapis/googleapis-mcp |
| Railway | MCP (official) | API token | `railway` | P2 | https://docs.railway.com/ai/mcp-server |
| Fly.io | REST (GraphQL API) | API token | `fly` | Backlog | https://api.fly.io/graphql — no MCP yet |
| Render | REST (REST API) | API key | `render` | Backlog | https://api.render.com/docs — no MCP yet |

### 14.3 P0 Integration Details

#### Datadog
- **Connector:** MCP — official server
- **Connector URL:** Hosted by Datadog, tenant provides their instance URL
- **Auth:** `DD-API-KEY` + `DD-APPLICATION-KEY` headers — store both in credentials JSONB
- **Key abilities after discovery:** `query_metrics`, `get_logs`, `list_monitors`, `get_dashboard`, `list_incidents`
- **Description enrichment needed:** Yes — Datadog tool names are terse. `query_metrics` needs enrichment to "Query Datadog metrics for a service, host, or tag over a time range"
- **Gotcha:** Datadog has separate API and App keys. Both required. App key scopes what data is accessible — document this clearly in the onboarding UI

#### AWS CloudWatch
- **Connector:** MCP — official AWS MCP server
- **Connector URL:** AWS official MCP server, self-hosted or via AWS tooling
- **Auth:** IAM — either access key + secret, or cross-account role ARN. Role ARN is preferred for security (no long-lived keys)
- **Key abilities after discovery:** `get_metric_statistics`, `filter_log_events`, `describe_alarms`, `get_metric_data`
- **Description enrichment needed:** Yes — `filter_log_events` needs "Search CloudWatch log groups for error patterns, stack traces, or specific messages"
- **Gotcha:** Requires region scoping. Store `region` in credentials JSONB alongside auth. A tenant running in us-east-1 and eu-west-1 may need two integrations
- **Why this matters competitively:** incident.io's AWS integration is inbound-only (CloudWatch fires a webhook to create an incident). They cannot query CloudWatch from their AI. Firefight can. This is the sharpest competitive differentiator in the P0 set

#### Grafana
- **Connector:** MCP — official server
- **Connector URL:** `https://{tenant-grafana-host}/mcp` — tenant provides their Grafana URL
- **Auth:** Service account token with Viewer role minimum, Editor for annotation writes
- **Key abilities after discovery:** `query_datasource`, `get_dashboard`, `list_dashboards`, `get_panel_data`, `create_annotation`
- **Description enrichment needed:** Moderate — Grafana tool names are reasonably descriptive
- **Gotcha:** Grafana Cloud vs self-hosted have different base URLs. Onboarding UI needs to ask

### 14.4 P1 Integration Details

#### Sentry
- **Connector:** MCP — official server
- **Auth:** Auth token with `project:read`, `event:read` scopes
- **Key abilities:** `list_issues`, `get_issue`, `list_events`, `get_event`, `resolve_issue`
- **Gotcha:** Sentry organizes by organization + project. Store `org_slug` in credentials JSONB. Discovery should scope to the tenant's projects only

#### New Relic
- **Connector:** MCP — community server, evaluate stability before shipping
- **Auth:** User API key
- **Key tools:** `nrql_query`, `get_application`, `list_alerts`, `get_deployment_markers`
- **Gotcha:** Community MCP, not officially supported by New Relic. Monitor for breakage. Consider building a thin REST adapter as a fallback if the community MCP goes stale
- **NRQL enrichment:** `nrql_query` needs rich description — "Run a NRQL query against New Relic to fetch metrics, traces, logs, or browser data. Use for custom metric queries when standard tools don't cover the need"

#### GCP Cloud Logging
- **Connector:** MCP — official Google MCP server
- **Auth:** Service account JSON key with `logging.logEntries.list` and `logging.logs.list` IAM permissions
- **Key tools:** `list_log_entries`, `list_logs`, `list_sinks`
- **Gotcha:** GCP service account JSON is large. Store as-is in credentials JSONB (it's encrypted). Don't try to extract fields — pass the whole JSON to the MCP client

### 14.5 Railway (P2)

Railway has an official MCP server that wraps their CLI. The abilities relevant to incident response:

- `get-logs` — fetch service logs (most useful)
- `list-services` — see what's deployed
- `deploy` — trigger a redeploy (write operation — permission-gate this carefully)
- `list-projects` — tenant project inventory

**Connector:** MCP. **Auth:** Railway API token — straightforward bearer token auth.

**Important:** Railway's MCP includes deployment actions (`deploy`, `set-variables`). These are write operations. When discovery runs and these abilities are created, set `enabled: false` by default and require explicit tenant opt-in before they can be invoked. Read-only abilities (`get-logs`, `list-services`) can default to enabled.

**Source:** https://docs.railway.com/ai/mcp-server — open source at https://github.com/railwayapp/railway-mcp-server

### 14.6 Fly.io and Render — REST Connectors (Backlog)

Neither has an MCP server. Previously marked as backlog because CLI wrapping is wrong, but they're now correctly handled as REST connectors using the `connector_type: "rest"` path:

- **Fly.io** — GraphQL API at `https://api.fly.io/graphql`. Abilities would cover: list apps, get app status, get logs, restart app. Auth: bearer token.
- **Render** — REST API at `https://api.render.com/v1`. Abilities would cover: list services, get service, retrieve logs, trigger deploy. Auth: API key.

For REST connectors, `Rest::DiscoveryService` reads either an OpenAPI spec (if available) or a static ability definition file maintained by Firefight. Fly and Render both have decent API docs — a static definition is the right approach until they ship MCPs.

### 14.7 Seeding First-Party Integrations at Tenant Onboarding

First-party integrations aren't manually connected by tenants via UI — they're offered as a structured onboarding flow. The `Integration` record is the same, but Firefight knows the MCP URL and credential shape upfront:

```ruby
module FirstParty
  CATALOG = {
    "datadog" => {
      name: "Datadog",
      connector_type: "mcp",
      connector_url: "https://mcp.datadoghq.com",  # or tenant-specific
      credential_fields: [
        { key: "DD-API-KEY", label: "API Key", type: "secret" },
        { key: "DD-APPLICATION-KEY", label: "Application Key", type: "secret" }
      ],
      description_overrides: {
        "query_metrics" => "Query Datadog metrics for a service, host, or tag over a time range. Use during incidents to check error rates, latency, or resource utilization.",
        "filter_log_events" => "Search Datadog logs for errors, exceptions, or patterns. Use to investigate what happened during an incident.",
        "list_monitors" => "List active Datadog monitors and their alert states. Use to see what's currently alerting.",
        "get_dashboard" => "Retrieve a Datadog dashboard. Use to get a snapshot of system health."
      }
    },
    "aws-cloudwatch" => {
      name: "AWS CloudWatch",
      connector_type: "mcp",
      connector_url: nil,  # tenant provides their regional endpoint
      credential_fields: [
        { key: "region", label: "AWS Region", type: "text" },
        { key: "access_key_id", label: "Access Key ID", type: "secret" },
        { key: "secret_access_key", label: "Secret Access Key", type: "secret" }
      ],
      description_overrides: {
        "get_metric_statistics" => "Fetch CloudWatch metric statistics for a namespace and metric name over a time period. Use to check CPU, memory, error counts, or custom metrics during an incident.",
        "filter_log_events" => "Search CloudWatch log groups for specific patterns, errors, or stack traces. The most useful tool for log investigation on AWS.",
        "describe_alarms" => "List CloudWatch alarms and their current states. Use to see what's in ALARM state right now.",
        "get_metric_data" => "Fetch multiple CloudWatch metrics at once using metric math expressions. Use for complex queries across multiple metrics."
      }
    }
    # ... etc
  }.freeze

  def self.seed_for_tenant(tenant, slug, credentials)
    catalog_entry = CATALOG.fetch(slug)
    integration = tenant.integrations.create!(
      name: catalog_entry[:name],
      slug: slug,
      connector_type: catalog_entry[:connector_type],
      connector_url: catalog_entry[:connector_url],
      credentials: credentials
    )
    # Discovery runs via after_create callback
    # After discovery, apply description overrides
    ApplyDescriptionOverridesJob.perform_later(
      integration.id,
      catalog_entry[:description_overrides]
    )
  end
end
```

### 14.8 Ability Description Override Job

```ruby
class ApplyDescriptionOverridesJob < ApplicationJob
  def perform(integration_id, overrides)
    integration = Integration.find(integration_id)
    overrides.each do |tool_name, override_description|
      integration.abilities.find_by(tool_name: tool_name)&.update!(
        description_override: override_description
      )
    end
  end
end
```

---

## 15. Competitive Analysis — incident.io & Rootly

### 15.1 What They Both Do (MCP Direction)

Both incident.io and Rootly expose **themselves** as MCP servers — so you can query their data from Claude or Cursor. This is the **opposite direction** to Firefight.

- **incident.io:** Launched a hosted MCP server at `https://mcp.incident.io/mcp` (public beta, March 2026). Exposes incident data, alerts, on-call schedules, post-mortems. Useful for querying incident.io from an IDE. Source: https://docs.incident.io/ai/remote-mcp
- **Rootly:** Launched their MCP server March 2025, went GA April 2026 with "up to 95% less tokens." Dynamically generates tools from their OpenAPI spec — clever approach, means they don't handwrite tool definitions. Source: https://docs.rootly.com/integrations/mcp-server / https://github.com/Rootly-AI-Labs/Rootly-MCP-server

Neither has built a **tenant-configurable inbound MCP gateway**. What Firefight is building — tenants connecting their own tools so the AI can use them — doesn't exist in either product.

### 15.2 incident.io's AWS Integration — The Key Gap

incident.io's AWS integration is CloudWatch → webhook → create incident. It is inbound alerting only. Source: https://incident.io/integrations/aws

They cannot query CloudWatch from their AI. Their AI SRE integrations with Datadog, Grafana, Splunk, etc. are all **hand-rolled, first-party, curated** — not a configurable gateway. Adding a new observability tool to their AI SRE requires their engineering team to build it.

Firefight's approach: add a new observability tool = tenant connects an MCP. No Firefight engineering required after the gateway is built.

### 15.3 Rootly's Approach

Rootly's MCP server is IDE-focused — "resolve incidents in under a minute without leaving your IDE." Their AI features are Slack-native for incident lifecycle (titles, summaries, post-mortems) but don't extend to querying observability tools. Their integration ecosystem is broad (Jira, PagerDuty, Datadog for alerting inbound) but again, no configurable outbound query layer.

### 15.4 Competitive Positioning Summary

| Capability | incident.io | Rootly | Firefight |
|---|---|---|---|
| Exposes self as MCP server | ✅ | ✅ | Planned (later) |
| AI can query Datadog during incident | ✅ (hand-rolled) | ❌ | ✅ (via gateway) |
| AI can query CloudWatch during incident | ❌ | ❌ | ✅ (via gateway) |
| Tenant can connect custom MCP | ❌ | ❌ | ✅ |
| Tenant can enable/disable individual abilities | ❌ | ❌ | ✅ |
| Scope-based permission per ability | ❌ | ❌ | ✅ |
| Adding new integration = code deploy | ✅ (their code) | ✅ (their code) | ❌ (tenant connects MCP) |
| Slack AI agent with tool access | ✅ | Limited | ✅ |

The sharpest differentiator to lead with: **Firefight can query CloudWatch, Grafana, and custom tools from the AI during an incident. Neither competitor can.**

---

## Appendix: Service Directory

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

  services/
    connectors/
      client_pool.rb         # Solid Cache backed pool, routes to Mcp:: or Rest:: client

    mcp/
      client.rb              # MCP JSON-RPC client (connector-specific)
      discovery_service.rb   # tools/list → Ability upserts (connector-specific)
      credential_refresher.rb

    rest/
      client.rb              # REST HTTP client (connector-specific)
      discovery_service.rb   # OpenAPI spec or static definition → Ability upserts

    abilities/
      invoker.rb             # Permission check + connector call + audit log
      errors.rb              # PermissionDenied, AbilityDisabled, etc.

    ai/
      agent.rb               # RubyLLM agentic loop
      find_ability_tool.rb
      get_ability_schema_tool.rb
      invoke_ability_tool.rb

    slack/
      command_handler.rb     # Parse command → explicit or AI path
      response_formatter.rb

    first_party/
      catalog.rb             # CATALOG constant + seed_for_tenant
      apply_description_overrides_job.rb

    permission_checker.rb

  jobs/
    integrations/
      discovery_job.rb       # Dispatches to Mcp:: or Rest:: DiscoveryService
      health_check_job.rb    # Dispatches to correct connector for health ping
    credential_refresh_job.rb
    audit_retention_job.rb

  controllers/
    slack_commands_controller.rb
    api/
      integrations_controller.rb
      abilities_controller.rb
```
