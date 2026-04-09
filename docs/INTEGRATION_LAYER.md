# Generic Integration Layer

## Goal

A tool registry that allows Firefight to call external services and receive events from them. Any consumer (Slack handler, AI agent, workflow step, dashboard UI) can discover and execute tools through the same interface. Users can connect any API or MCP server without waiting for first-party support.

## Design Principles

- **Integration layer is standalone.** It's a tool registry with an execution interface, not a workflow feature. Workflows are one consumer, not the only one.
- **Tools are organized by domain.** AI agents and workflows discover tools through a two-level hierarchy (domain → tools), not a flat list.
- **Same interface for all tool types.** MCP server, REST API, or built-in Ruby class — callers don't care how the tool is implemented.
- **Human-in-the-loop is built in.** Any tool can require confirmation before executing. The caller gets a pending result and resumes on approval.
- **First-party integrations are pre-packaged generic integrations.** Same models, same execution path, just pre-configured with polished UI and default mappings.

## Consumers

Tools can be called from four places:

| Consumer | Example |
|----------|---------|
| **Slack** | User runs `/ff jira` → handler calls the Jira create-issue tool |
| **AI agent** | Postmortem generator calls tools to gather context; analysis agent creates tickets |
| **Workflows** | "When SEV1 incident created, call PagerDuty page-oncall tool" |
| **Dashboard UI** | User clicks "Create Jira ticket" button on incident page |

All consumers call the same execution interface. No special paths per consumer.

## Data Model

### `integrations`

A connected external service instance. One workspace can have multiple integrations (e.g., Jira Production, Jira Staging).

| Field | Type | Description |
|-------|------|-------------|
| `workspace_id` | FK | Owning workspace |
| `name` | string | Display name ("Jira Production") |
| `provider` | string | Provider type: `custom_api`, `mcp_server`, `jira`, `linear`, `pagerduty`, `datadog`, `github` |
| `config` | jsonb | Connection config (base URL, MCP endpoint, etc.) |
| `credentials` | encrypted | Auth credentials (API token, OAuth tokens, MCP auth) |
| `status` | enum | `active`, `inactive`, `error` |
| `error_message` | text | Last connection error, if any |
| `last_connected_at` | datetime | Last successful connection/health check |

Built-in providers (`jira`, `linear`, etc.) use provider-specific credential shapes. `custom_api` and `mcp_server` use generic shapes.

### `integration_tools`

An action that can be performed against an integration. Each tool has typed inputs, belongs to a domain, and can be called by any consumer.

| Field | Type | Description |
|-------|------|-------------|
| `integration_id` | FK | Parent integration |
| `domain` | enum | Tool category (see domains below) |
| `name` | string | Display name ("Create Issue") |
| `slug` | string | Stable identifier (`create-issue`) |
| `description` | text | What this tool does (used by AI for tool selection) |
| `input_schema` | jsonb | JSON Schema defining expected parameters |
| `tool_type` | enum | `mcp`, `rest_api`, `built_in` |
| `tool_config` | jsonb | Type-specific execution config (see below) |
| `confirmation_required` | boolean | Require human approval before executing (default: false) |
| `enabled` | boolean | Can be disabled without deleting |
| `position` | integer | Ordering within domain |

**tool_config by tool_type:**

```ruby
# rest_api
{
  method: "POST",
  path: "/rest/api/3/issue",                    # appended to integration base_url
  headers: { "X-Custom" => "value" },            # merged with integration default headers
  payload_template: {                            # Liquid template, rendered with input params
    fields: {
      project: { key: "{{ project_key }}" },
      summary: "{{ summary }}",
      issuetype: { name: "{{ issue_type }}" }
    }
  },
  response_mapping: {                            # extract fields from response
    id: "$.id",
    key: "$.key",
    url: "$.self"
  }
}

# mcp
{
  tool_name: "create_issue"                      # MCP tool name on the connected server
}

# built_in
{
  handler_class: "Integrations::Jira::CreateIssue"  # Ruby class that executes the action
}
```

### `integration_webhook_endpoints`

Inbound webhook receiver. External services send events here, which trigger incident actions or tool calls.

| Field | Type | Description |
|-------|------|-------------|
| `integration_id` | FK | Parent integration |
| `name` | string | Display name ("Datadog Alert Webhook") |
| `slug` | string | Unique slug (generates URL: `/webhooks/integrations/:slug`) |
| `secret` | string | HMAC signing secret for verification |
| `active` | boolean | Enabled/disabled |
| `conditions` | jsonb | When to act (payload matching rules) |
| `action_type` | enum | `create_incident`, `update_incident`, `call_tool`, `trigger_workflow` |
| `action_config` | jsonb | What to do when triggered (field mappings, tool slug, workflow class) |
| `last_received_at` | datetime | Last webhook received |

**conditions format:**

```ruby
# Match when payload field meets criteria
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
# create_incident
{
  field_mappings: {
    name: "{{ alert.title }}",
    summary: "{{ alert.message }}",
    severity_slug: "sev1",                       # static or "{{ alert.severity_map }}"
    source: "datadog"
  }
}

# update_incident
{
  incident_lookup: { source: "{{ alert.incident_id }}" },
  field_mappings: { summary: "{{ alert.message }}" }
}

# call_tool
{
  tool_slug: "acknowledge-alert",
  input_mappings: { alert_id: "{{ alert.id }}" }
}

# trigger_workflow (future — when workflow engine supports custom triggers)
{
  workflow_class: "AlertResponseWorkflow",
  context_mappings: { alert_id: "{{ alert.id }}", severity: "{{ alert.severity }}" }
}
```

### `tool_executions`

Audit log of every tool call. Tracks who called what, when, with what result.

| Field | Type | Description |
|-------|------|-------------|
| `integration_tool_id` | FK | Tool that was executed |
| `incident_id` | FK, optional | Related incident |
| `triggered_by_type` | string | Polymorphic: `WorkspaceMembership`, `SolidWorkflow::Step`, `AiAgent` |
| `triggered_by_id` | bigint | Polymorphic ID |
| `input` | jsonb | Parameters sent to the tool |
| `output` | jsonb | Response from the tool |
| `status` | enum | `pending`, `awaiting_confirmation`, `confirmed`, `executing`, `succeeded`, `failed`, `rejected` |
| `error_message` | text | Error details on failure |
| `confirmed_by_id` | FK, optional | User who approved (if confirmation_required) |
| `confirmed_at` | datetime | When approved |
| `executed_at` | datetime | When execution completed |

---

## Tool Domains

Tools are grouped by domain. AI agents discover tools through a two-level hierarchy: pick relevant domains first, then see tools within those domains. This prevents the AI from getting a flat list of hundreds of tools.

| Domain | Description | Example tools |
|--------|-------------|---------------|
| `incidents` | Incident lifecycle operations | Create incident, update severity, close incident, assign lead |
| `communication` | Messaging and notifications | Post to channel, send DM, send email, post announcement |
| `ticketing` | Issue tracking | Create Jira issue, update Linear ticket, link ticket to incident |
| `monitoring` | Alert and monitoring operations | Acknowledge alert, silence alert, get metrics, create downtime |
| `source_control` | Code and deploy operations | Get recent commits, get PR status, link PR, trigger rollback |
| `catalogue` | Service catalogue operations | Lookup service, get owner, get dependencies, get runbook |
| `internal` | Firefight internal operations | Update custom field, add timeline entry, create action item |

The `internal` domain contains built-in Firefight operations exposed as tools so AI agents and workflows can use the same interface for internal and external actions.

### AI Tool Selection

When an AI agent needs to act, it receives domain descriptions and selects relevant domains. Then it sees only the tools within those domains.

```
Step 1: Agent sees domain list with descriptions
  → Selects: ticketing, communication

Step 2: Agent sees tools in selected domains
  → ticketing: create-jira-issue, update-jira-issue, link-ticket
  → communication: post-channel-message, send-dm

Step 3: Agent calls specific tool
  → create-jira-issue(project: "OPS", summary: "...", incident_id: 123)
```

This keeps the tool selection focused and reduces hallucination.

---

## Execution Flow

### Standard execution

```
Caller (any consumer)
  → IntegrationToolExecutor.execute(tool, params:, triggered_by:, incident:)
    → Validate params against tool.input_schema
    → Create ToolExecution (status: pending)
    → If tool.confirmation_required?
      → Set status: awaiting_confirmation
      → Send confirmation request (Slack message / dashboard notification)
      → Return execution (caller handles async)
    → Execute based on tool.tool_type:
      → rest_api: render payload template, HTTP request, map response
      → mcp: call MCP server with tool_name and params
      → built_in: call handler_class.execute(params)
    → Update ToolExecution (status: succeeded/failed, output/error)
    → Return execution with result
```

### Human-in-the-loop

```
Tool has confirmation_required: true

1. Caller requests execution
   → ToolExecution created (status: awaiting_confirmation)
   → Notification sent to incident channel or dashboard
     "AI wants to create a Jira ticket: [summary]. Approve / Reject?"

2a. User approves
   → IntegrationToolExecutor.confirm(execution, confirmed_by:)
   → Tool executes normally
   → If caller was a workflow step, step resumes with output

2b. User rejects
   → IntegrationToolExecutor.reject(execution, rejected_by:)
   → Status set to rejected
   → If caller was a workflow step, step receives rejection result
```

### Inbound webhook

```
External service → POST /webhooks/integrations/:slug
  → IntegrationWebhooksController#receive
    → Find endpoint by slug
    → Verify signature (HMAC-SHA256 with endpoint.secret)
    → Parse JSON payload
    → Evaluate conditions against payload
    → If conditions match:
      → Route to action handler based on action_type
      → create_incident: call IncidentLifecycleService.create(mapped_fields)
      → update_incident: find incident, call service.update(mapped_fields)
      → call_tool: find tool by slug, execute with mapped params
      → trigger_workflow: start workflow with mapped context
    → Record webhook receipt
    → Return 200
```

---

## MCP Integration

MCP (Model Context Protocol) servers expose tools over a standard protocol. Firefight connects to MCP servers as integrations and discovers their tools automatically.

### Connection flow

```
1. User adds MCP integration:
   → Provides MCP server endpoint + auth
   → Firefight connects and calls tools/list
   → Each MCP tool becomes an IntegrationTool (tool_type: mcp)
   → Tool name, description, and input_schema imported from MCP server

2. Tool sync:
   → Periodic or on-demand refresh of available tools
   → New tools added, removed tools disabled
   → Schema changes updated
```

### Execution

MCP tool execution is a standard MCP `tools/call` request. The integration stores the server endpoint and auth. The executor sends the tool name and params, receives the result.

---

## REST API Tools

For services without MCP support, users define tools as HTTP request templates.

### Definition

User provides:
- HTTP method and path (relative to integration base URL)
- Payload template (Liquid syntax with input param interpolation)
- Response mapping (JSONPath expressions to extract output fields)
- Optional custom headers

### Execution

```
1. Render payload template with input params
2. Build full URL: integration.config.base_url + tool.tool_config.path
3. Set headers: integration default headers + tool custom headers + auth
4. Make HTTP request
5. Parse response
6. Apply response_mapping to extract output fields
7. Return mapped output
```

### Authentication

Stored on the integration, not per-tool:

| Auth type | Config |
|-----------|--------|
| `bearer_token` | `{ token: "..." }` |
| `basic_auth` | `{ username: "...", password: "..." }` |
| `api_key_header` | `{ header_name: "X-Api-Key", key: "..." }` |
| `oauth2` | `{ client_id, client_secret, token_url, access_token, refresh_token, expires_at }` |

OAuth2 tokens refresh automatically before expiry.

---

## Built-in Tools (First-Party Integrations)

First-party integrations are pre-packaged on the same generic layer. They use `tool_type: built_in` with a Ruby handler class that encapsulates the provider-specific logic.

### What a first-party integration package contains

```
app/integrations/jira/
  setup.rb              # Creates Integration + IntegrationTools + WebhookEndpoints
  tools/
    create_issue.rb     # Built-in tool handler
    update_issue.rb
    link_issue.rb
    sync_status.rb      # Bidirectional sync (commercial)
  webhook_parsers/
    issue_updated.rb    # Parses Jira webhook payload into action_config format
  templates/
    default_tools.yml   # Pre-configured tool definitions
    default_webhooks.yml # Pre-configured webhook endpoint definitions
```

### Setup flow

```
1. User adds Jira integration (OAuth flow or API token)
2. Jira::Setup.install(integration) runs:
   → Creates IntegrationTools from default_tools.yml (built_in type)
   → Creates IntegrationWebhookEndpoints from default_webhooks.yml
   → Pre-configures field mappings for common Jira fields
3. User can customize: add/remove tools, adjust mappings, toggle confirmation
```

The user sees the same tool/webhook interface as custom integrations. They can modify anything the setup created.

---

## Relationship to Existing Systems

### Event system

The existing `EventRouter` routes domain events to subscribers. Integration tools are NOT triggered by the event router directly — that's what workflows are for (or will be for). The event router delivers to webhooks (existing) and will deliver to workflow triggers (future).

```
IncidentEvent → ProcessDomainEventJob → EventRouter
  → Webhooks::EventSubscriber (existing — delivers to user-configured webhooks)
  → Workflows::EventSubscriber (future — triggers automation workflows)
```

Workflows call integration tools as step actions. The integration layer doesn't subscribe to events.

### Adapter pattern

The existing `WorkspaceAdapter` handles Slack/Teams platform operations. Integration tools handle everything else (Jira, Datadog, PagerDuty, custom APIs).

These are separate systems:
- `WorkspaceAdapter` — platform the workspace runs on (Slack, Teams). One per workspace.
- `Integration` — external services connected to the workspace. Many per workspace.

### Workflow engine

SolidWorkflow steps can call integration tools through the executor. A workflow step that calls a tool looks like:

```ruby
def create_jira_ticket(workflow:, step:, input:)
  tool = workflow.subject.workspace.integration_tools.find_by!(slug: "jira-create-issue")
  execution = IntegrationToolExecutor.execute(
    tool,
    params: { summary: input["incident_name"], project: "OPS" },
    triggered_by: step,
    incident: workflow.subject
  )
  { ticket_id: execution.output["id"], ticket_key: execution.output["key"] }
end
```

If the tool requires confirmation, the workflow step pauses until the user approves.

---

## Security

### Credential storage

Integration credentials are encrypted at rest using Rails encrypted attributes. Credentials are never exposed in API responses, logs, or tool execution records.

### Webhook verification

Inbound webhooks are verified using HMAC-SHA256 signatures. The signing secret is unique per endpoint and auto-generated on creation.

### Tool execution scoping

All tool execution is scoped to a workspace. A tool from workspace A cannot be called in the context of workspace B. Workspace isolation is enforced at the executor level.

### Audit trail

Every tool execution is recorded in `tool_executions` with full input/output, who triggered it, and the result. This provides a complete audit trail for compliance and debugging.

---

## Implementation Phases

### Phase 1: Tool Registry + REST API Tools

Build the core integration layer with REST API tool support.

**Models:**
- `Integration`
- `IntegrationTool`
- `ToolExecution`

**Services:**
- `IntegrationToolExecutor` — validate, execute, record
- `RestApiToolExecutor` — HTTP request execution with template rendering
- `IntegrationToolValidator` — validate input params against schema

**What works after Phase 1:**
- User creates a custom API integration (e.g., Jira REST API)
- User defines tools with HTTP templates
- Tools can be called from Slack handlers and dashboard UI
- Full execution audit trail

### Phase 2: Inbound Webhooks

Add the webhook receiver for external events.

**Models:**
- `IntegrationWebhookEndpoint`

**Controllers:**
- `IntegrationWebhooksController` — receive, verify, route

**Services:**
- `WebhookConditionEvaluator` — evaluate payload conditions
- `WebhookActionRouter` — route to create_incident / update_incident / call_tool

**What works after Phase 2:**
- External services send webhooks to Firefight
- Webhooks can auto-create or update incidents
- Webhooks can trigger tool calls

### Phase 3: MCP Support

Add MCP server connections and tool discovery.

**Services:**
- `McpToolExecutor` — MCP protocol client
- `McpToolSync` — discover and sync tools from MCP server

**What works after Phase 3:**
- Users connect MCP servers as integrations
- Tools auto-discovered from MCP server
- MCP tools callable from same interface as REST API tools

### Phase 4: Human-in-the-Loop

Add confirmation flow for sensitive tool executions.

**Models:**
- Add `confirmation_required` to `IntegrationTool`
- Add `confirmed_by_id`, `confirmed_at` to `ToolExecution`

**Services:**
- Confirmation notification (Slack message with approve/reject)
- `IntegrationToolExecutor.confirm` / `.reject`
- Workflow step pause/resume on confirmation

**What works after Phase 4:**
- Any tool can require human approval before executing
- AI agents and workflows pause for confirmation
- Users approve/reject from Slack or dashboard

### Phase 5: First-Party Integrations

Build pre-packaged integrations on top of the generic layer.

**Priority order:**
1. Jira (most requested in incident management)
2. Linear
3. PagerDuty
4. GitHub

Each provides: setup wizard, pre-configured tools, webhook parsers, field mappings.

### Phase 6: AI Agent Tool Access

Expose integration tools to AI agents with domain-based discovery.

**Services:**
- `ToolDiscoveryService` — list domains, list tools by domain, format for LLM tool-use
- AI agents call tools through `IntegrationToolExecutor` (same as all other consumers)

**What works after Phase 6:**
- AI agents discover and call integration tools during analysis
- Domain hierarchy prevents tool selection confusion
- Confirmation gates protect sensitive actions

---

## Key Files (Planned)

```
app/models/
  integration.rb
  integration_tool.rb
  integration_webhook_endpoint.rb
  tool_execution.rb

app/services/
  integration_tool_executor.rb          # Main execution interface
  integration_tool_validator.rb         # Input schema validation
  integrations/
    rest_api_tool_executor.rb           # HTTP request execution
    mcp_tool_executor.rb                # MCP protocol client (Phase 3)
    mcp_tool_sync.rb                    # MCP tool discovery (Phase 3)
    webhook_condition_evaluator.rb      # Inbound webhook condition matching
    webhook_action_router.rb            # Route inbound webhook to action
    tool_discovery_service.rb           # Domain-based tool discovery for AI (Phase 6)

app/controllers/
  integration_webhooks_controller.rb    # Inbound webhook receiver

app/integrations/                       # First-party integration packages (Phase 5)
  jira/
  linear/
  pagerduty/
  github/

db/migrate/
  create_integrations.rb
  create_integration_tools.rb
  create_tool_executions.rb
  create_integration_webhook_endpoints.rb
```
