# AI Agent Roadmap

How we get from the current platform to agent-driven incident response, then to autonomous remediation. Four phases, each independently shippable.

## Guiding principle

We are a small team competing against well-funded incumbents. We do not win by shipping more integrations than incident.io. We win by building **primitives that compound**: a tool framework so good that customers (and the open-source community) fill the long tail themselves.

Every "integration," every MCP server, every customer-built Slack command, every first-party connector is the same primitive: **a tool the agent (or a human, or an external AI like Claude Code) can call**. Our job is to build that primitive once, then ship a curated portfolio of first-party tools on top of it as proof.

---

## The six-month platform milestone

The headline goal for the next six months is **not** "Firefight fixes incidents autonomously." It is shipping the platform such that **any agent** (ours, the customer's, or an external AI agent like Claude Code) can investigate and act on incidents with safety enforced by Firefight.

**At month 6, what ships:**
- Full tool registry with every ingestion path live (system / first-party / workspace HTTP / MCP / custom slash commands)
- Bi-directional MCP: Firefight consumes external MCP servers **and** exposes itself as an MCP server to external agents
- All safety primitives: risk classification, approval tiers, blast radius scoping, reversibility metadata, rate limits, shadow mode, kill switch
- Machine-executable runbooks
- Long-running agent runtime on `SolidWorkflow`
- Closed-loop verification helpers
- A working read-only investigator agent as proof
- Two flagship first-party integrations (GitHub, Datadog) as dogfood

**At month 6, what does NOT ship:**
- Firefight's own autonomous remediation agent (months 7-18)
- Confidence calibration (research-grade hard, deferred)
- A broad first-party connector portfolio (demand-pulled, ongoing)

**The pitch at month 6:** "Firefight: the open-source incident operations platform. Bring your own agent or use ours."

This is a deliberately platform-first milestone. Revenue at month 6 comes from the platform being useful to customers wiring up their own remediation flows, plus our own non-autonomous agent capabilities, **before** we ship the autonomous Firefight agent. That agent comes later and is the upsell, not the foundation.

---

## Current state (May 2026)

Foundation that already exists in the codebase. Don't rebuild any of this.

### Core incident domain
- `Incident` with `custom_fields` jsonb, `IncidentFieldDefinition`
- `IncidentSeverity`, `IncidentStatus`, `IncidentLifecycleStage`
- `IncidentEvent` timeline with 20+ event types
- `IncidentUpdate` for structured comms
- `IncidentAction` (ACTION + FOLLOWUP types)
- `Postmortem` with structured sections
- `IncidentRelationship` (DUPLICATE marker, partial merge)
- `IncidentTranscriptCache` (Redis-backed Slack message capture)
- `IncidentRole`, `IncidentRoleAssignment`

### Org / catalog
- Full catalog backend: `CatalogEntry`, `CatalogType`, `CatalogAttributeDefinition`, `CatalogEntryRelationship`
- `Workspace`, `WorkspaceMembership`, `User`
- Outbound `Webhook` + `WebhookDelivery`

### Infrastructure
- `SolidWorkflow` engine (workflow + step + event audit trail, retries, pause/resume, sweeper)
- `firefight_ai` engine on RubyLLM (currently hardcoded to claude-sonnet-4-6)
- Existing AI services: `IncidentResponder`, `PostmortemGenerator` (prompts inline)
- Public REST API at `/api/v1/` with `ApiKey` and `IdempotencyKey`
- Slack adapter at `app/adapters/slack/`

### What is missing relative to incident.io's agent map
1. **Foundation for agents**: tool registry, prompt registry, agent run model, semantic search, memory
2. **Inbound data**: alert ingestion, alert routing rules
3. **Knowledge**: runbooks, docs search
4. **The extensible tool layer**: first-party integrations, workspace HTTP tools, MCP gateway (both directions), custom slash commands
5. **Remediation primitives**: write-access tool framework, safety policy engine, closed-loop verification, machine-executable runbooks
6. **On-call vertical**: schedules, overrides, cover requests, maintenance windows (deferred, separate product)

---

## Phase 0: Prerequisites already in flight

Two pieces of domain work landing now. Doable in parallel.

### Runbooks
New first-class primitive. Markdown content authored by humans, indexed for retrieval, linked to catalog entries.

```
Runbook
  workspace_id, title, slug, content (markdown)
  status (draft / published / archived)
  authored_by_id, last_edited_by_id
  version, created_at, updated_at

RunbookCatalogLink (many-to-many to catalog entries)
RunbookAlertSignatureLink (many-to-many, optional)
RunbookVersion (audit history)
```

### Alert API
Inbound webhook receivers per provider plus a normalized `Alert` model.

```
AlertSource
  workspace_id, name, provider
  secret_token (encrypted), config jsonb
  endpoint_path (unique)

Alert
  alert_source_id, workspace_id
  external_id, fingerprint
  title, description, severity_raw, payload jsonb
  status (firing / resolved)
  received_at, resolved_at
  incident_id (nullable)

AlertRoutingRule
  workspace_id, name, priority
  conditions jsonb
  action (auto_create_incident / attach_to_incident / notify_only / drop)
  target_severity_id, target_team, target_channel
```

Flow: provider POSTs to `/api/v1/alerts/{endpoint_path}`, ingestion service normalizes, dedup by fingerprint, router evaluates rules, first match fires its action.

---

## Phase 1: Agent foundation on internal data (months 1-2)

Ship a real agent that uses only data Firefight already owns. No external integrations yet. Validates the agent loop before framework work.

### Hard blockers

**1. Tool registry (scoped from day one)**
Single most important architectural decision. One place to register a tool. Designed so phase 2 plugs in without restructuring.

- **System scope**: code-defined, always available
- **Workspace scope**: per-tenant tools (added in phase 2)
- **User scope**: optional later

Interface: `{ key, description, json_schema, scope, executor, permission_check, audit_metadata, side_effect_class }`. The `side_effect_class` field (read / write / dangerous) is reserved here even though phase 1 only ships read tools, so phase 3 doesn't need a schema migration.

**2. Prompt registry**
```
Prompt
  key (e.g., "incident_responder.system")
  version (semver)
  template, metadata jsonb
  status (draft / active / retired)

PromptOverride (per-workspace)
  workspace_id, prompt_key, template, version_pin
```

**3. Semantic search + embeddings (pgvector)**
Embed and index past incidents, postmortems, runbooks, optionally transcript summaries. Graph relationships stay in Postgres FKs. Multi-hop queries via recursive CTEs.

**4. Agent run model (operational record in Postgres)**
```
AgentRun
  workspace_id, incident_id (nullable FK), started_by_id (nullable FK)
  agent_key, status, input jsonb, final_output jsonb
  prompt_version_id, model
  total_tokens_in, total_tokens_out, total_cost_cents
  started_at, finished_at, duration_ms

AgentToolCall
  agent_run_id, sequence, tool_key, scope
  input_json, output_json
  status, error_message
  started_at, finished_at, duration_ms
```

Postgres, not Tinybird: FK to incident/workspace/user, cascade matters, read pattern is "show runs for this incident," volume is low. Tinybird is the right home for analytics later, fed by a stream from the same insert.

### Soft blockers (build before second agent)
- Eval harness: fixture-based replay of past incidents, scored
- Per-workspace LLM config
- Rate limiting / cost tracking per workspace, per agent

### What phase 1 unlocks
- Auto-triage on alert ingestion
- "Have we seen this before?" semantic search
- Runbook lookup in context
- Channel summarization
- Auto-drafted status updates in multiple tones
- Auto-extracted actions at incident close
- Better postmortems with historical patterns
- Severity disagreement check
- Ownership routing from catalog

Sellable product on its own.

### Phase 1 build order
1. Tool registry + prompt registry
2. Agent run model + `AgentToolCall`
3. pgvector setup + embedding pipeline
4. Refactor existing AI services onto the registry (no behavior change)
5. AgentIncident v0 with system-scope tools
6. Auto-triage agent triggered on `Alert` ingestion
7. Slash-command surface
8. Eval harness with 20-50 fixture incidents

---

## Phase 2: Extensible tool layer + bi-directional MCP (months 3-4.5)

The leverage phase. One framework that unifies first-party integrations, workspace tools, MCP, and custom Slack commands. Plus exposing Firefight itself as an MCP server, which changes the entire product surface.

### The unification

One framework, five paths in **and** one path out:

| Path | Defined by | Use case |
|---|---|---|
| System (in) | Firefight code | `incident.update`, `catalog.search` |
| First-party integration (in) | Firefight engineering | `github.list_recent_prs`, `datadog.query_logs` |
| Workspace HTTP tool (in) | Customer admin via UI | `acme.restart_billing_service` |
| MCP client (in) | Customer points at MCP server | Server's tools auto-register |
| Custom slash command (in) | Customer maps Slack command | `/postmortem-status` runs a tool |
| **MCP server (OUT)** | Firefight exposes its registry | Claude Code, Cursor, Cline call Firefight tools |

The agent runtime and the safety engine cannot tell which path a tool came from. The same protocol that lets us consume MCP also lets us expose MCP. Symmetric.

### What to build

**1. `Integration` + `IntegrationCapability` schema**
```
Integration
  workspace_id, provider, name, status
  credentials_encrypted jsonb
  config jsonb
  installed_at, last_used_at

IntegrationCapability
  integration_id, capability_key
  enabled, config jsonb
```

**2. Secrets and auth framework**
- Encrypted credential store (one model, every integration path uses it)
- OAuth handshake helpers (parameterized per provider)
- API key + per-call header injection
- Token refresh background job
- Audit log of install / rotate / revoke

**3. HTTP tool primitive (workspace-defined)**
Workspace admin defines: endpoint URL, method, auth, JSON schema for inputs, optional output schema, optional response transform. Becomes a tool under workspace scope.

**4. MCP client (consuming external MCP servers)**
- Admin pastes MCP server URL + auth
- We discover tools via MCP protocol
- Each becomes a tool in the registry, marked with `mcp_source_id`
- Calls proxy through our system so audit + rate limit + safety engine apply

**5. MCP server (exposing Firefight to external agents)**

This is the move. Same primitive in reverse.

Every workspace gets an MCP endpoint:
```
mcp://firefight.{your-domain}/workspaces/{workspace_id}
auth: workspace API key with mcp scope
```

Through that endpoint, anything in the tool registry can be exposed:
- System tools (incident operations, catalog lookups, runbook search)
- First-party integration tools (whichever ones the workspace has installed)
- Workspace HTTP tools
- Optionally: tools proxied from other MCP servers the workspace consumes

What this unlocks:
- Engineer in Claude Code: "what's happening with `inc-7450`?" -> Claude Code calls Firefight MCP tools -> returns incident, transcript, related runbook, similar past incidents, without leaving the IDE
- Engineer in Cursor: "check Datadog logs for billing-service in the last 10 min" -> routes through our Datadog integration via MCP
- Engineer at 2am: investigates from their terminal using their existing AI coding agent, hands off to the Firefight Slack agent if escalation needed
- Internal: Firefight engineers use Firefight via their own MCP. Deepest possible dogfood.

Why this matters strategically:
- **Distribution through dev tools.** Every Claude Code / Cursor / Cline user is a potential Firefight user.
- **Defensive moat.** Incumbents would have to retrofit this.
- **Architectural validation.** If our MCP server can serve every tool with correct auth/audit/safety, the inverse (consuming external MCP servers) is provably symmetric. Two paths share code.
- **Open-source compound.** "Use your self-hosted Firefight from Claude Code" is a story that writes itself.

Implementation: roughly 4-5 weeks slotted inside this phase.
- MCP server adapter walks the tool registry, advertises capabilities (1-2 weeks)
- Extend `ApiKey` with `mcp` scope and tool-level allow list (1 week)
- Streaming protocol bits (1 week)
- Per-workspace tool exposure controls in the UI (1 week)
- Documentation + Claude Code config example (a few days)

**6. Custom slash command surface**
Workspace maps a Slack command (e.g., `/restart`) to a tool key. Dispatch goes through the tool registry so permission + audit + safety apply uniformly.

**7. Flagship first-party integrations (proof and marketing)**
Ship two, as customers of the framework, not as bespoke code:
- **GitHub**: commits, PRs, recent merges, file content read. High-leverage for postmortems and deploy correlation.
- **Datadog**: logs + metrics + APM. Most common observability stack.

Anything else (Prometheus, Grafana, Splunk, Honeycomb, Snowflake) waits until sales asks, a contributor builds it, or we have spare cycles.

### Phase 2 build order
1. `Integration` + `IntegrationCapability` + encrypted credential store
2. OAuth + API key helpers
3. HTTP tool primitive (workspace scope, UI)
4. GitHub integration as first dogfood
5. Refactor reusable parts back into the framework
6. MCP client (consuming) + tool discovery + audit proxy
7. **MCP server (exposing)** + per-workspace exposure controls
8. Custom slash command surface
9. Datadog integration as second dogfood
10. Documentation, integration contributor guide, Claude Code setup guide

---

## Phase 3: Remediation primitives + investigator agent (months 5-6)

This is where the **month 6 platform milestone** lands. All primitives that an autonomous agent would need are in place. We ship a read-only investigator agent as proof. The autonomous remediation agent itself is deferred to phase 4.

### Write-access tool primitive
The tool registry's `side_effect_class` field (reserved in phase 1) gets populated. Every write tool declares:
- `risk_class` (low / medium / high / catastrophic)
- `reversibility` (auto_reversible / manually_reversible / irreversible) plus reverse-tool key if applicable
- `idempotency` (idempotent / non_idempotent with idempotency key support)
- `blast_radius` (single_resource / service / region / global)

Same framework applies whether the tool is a first-party integration, a workspace HTTP tool, or an MCP-proxied tool.

### Safety / policy engine
The hard part. Wraps every tool call uniformly regardless of source.

- **Approval tiers**: low auto-runs, medium requires 1 human ack, high requires 2 acks plus specific role, catastrophic always blocked from autoexecute
- **Per-workspace policy overrides**: admin can downgrade a tool's required approval level for their org, with audit
- **Shadow mode per skill**: agent logs what it *would* do for N invocations or N days before execution permission is granted
- **Rate limits**: per tool, per service, per workspace
- **Kill switch + global circuit breaker** with per-workspace overrides
- **Per-team / per-service opt-in** to autoexecute specific skills

Schema:
```
ToolPolicy
  workspace_id, tool_key
  required_approval_tier (none / one_ack / two_acks / blocked)
  required_approval_role_id (optional)
  rate_limit_per_hour, rate_limit_per_day
  shadow_mode_until (timestamp)

ToolApproval
  agent_run_id, tool_call_id
  requested_at, approved_by_id, approved_at
  rejected_by_id, rejected_at
  expires_at
```

### Closed-loop verification
- Tools can declare a verification probe (a read tool plus assertion)
- After a write tool runs, the agent runtime schedules the probe at intervals (1 min, 5 min, 15 min)
- If probe asserts failure, runtime calls the reverse-tool if available, escalates to human if not
- Lives on top of `SolidWorkflow` so resume/retry/audit work

### Machine-executable runbooks
Extend the `Runbook` model:
```
Runbook
  ... existing fields ...
  executable_steps jsonb (optional)
  # each step: { tool_key, input_template, assertion, on_failure }

RunbookExecution (subtype of AgentRun)
  runbook_id, step_index, status
```

Markdown runbooks remain. Executable steps are an optional layer on top, parameterized and assertable.

### Long-running agent runtime
`SolidWorkflow` extended so steps can be dynamically generated by the LLM rather than declared statically.
- New workflow type: `DynamicAgentWorkflow`
- Each LLM tool-call decision creates a new step
- Step retries, pauses, audit replay all work as before
- Workflow can run for hours, pause for human approval, resume

This is the substrate phase 4's autonomous agent will use.

### Investigator agent (read-only, on the framework, as proof)
Composes parallel tool calls across whatever the workspace has installed.
- On alert ingestion (or `@firefight investigate inc-X`), runs in parallel:
  - Similar past incidents (system tool)
  - Relevant runbook (system tool)
  - Catalog lookup for affected services (system tool)
  - Recent deploys (GitHub integration if installed)
  - Recent log spikes (Datadog integration if installed)
  - Recent metric anomalies (Datadog integration if installed)
  - Anything from MCP servers the workspace has connected
- Posts hypothesis with citations to the incident channel within 60 seconds
- Each citation links back to the underlying tool call

Read-only. No remediation. But it proves every primitive built in phases 1-3 works together.

### Audit replay UI
View any `AgentRun` step by step: input, prompt version, tool calls in order, outputs, decisions, approvals, final state. Essential for trust and for debugging the agent.

### Phase 3 build order
1. Write-access tool primitive (extends existing tool schema)
2. `ToolPolicy` + `ToolApproval` models
3. Safety engine middleware on tool dispatch
4. Shadow mode capability
5. Kill switch + rate limiter
6. `RunbookExecution` + executable runbook schema
7. `DynamicAgentWorkflow` on `SolidWorkflow`
8. Closed-loop verification (probe scheduling, reverse-tool dispatch)
9. Investigator agent on the new runtime
10. Audit replay UI

**At the end of phase 3 (month 6), the platform is complete.** Any agent (ours, customer's, Claude Code via MCP) can investigate and act with safety enforced. The autonomous Firefight agent is the **next** product, built on top.

---

## Phase 4: Autonomous Firefight + connector breadth (months 7-18+)

Now the platform exists, we build the **Firefight-branded autonomous agent** on top of it, and we grow the first-party connector portfolio in response to demand.

### Firefight autonomous remediation agent
Built on the phase 3 primitives. Specifically:

- Uses `DynamicAgentWorkflow` for long-running runs
- Calls only tools in the registry with appropriate `side_effect_class`
- Subject to the safety engine like any other agent
- Multi-agent specialization: diagnostic / remediation / comms / planner

The first version is heavily gated:
- Specific, well-defined remediation skills only (rollback + restart + flag toggle)
- Approval-required by default
- Per-workspace opt-in, per-skill, per-service
- Shadow mode for weeks before any skill is promoted to autoexecute

### Confidence calibration (research)
Eventually, the agent should know when to ask vs when to act. ">90% match to known pattern" autoruns the runbook; "40% match" proposes only. Genuinely research-grade hard. Most teams ship without it and rely on conservative approval gates. We do the same on day one and revisit later.

### Demand-pulled first-party connectors
Only build first-party when:
- A paying customer asks and won't accept "configure the workspace HTTP tool yourself"
- More than three churned or stalled deals named it as a blocker
- The community has not built it after six months

Likely first additions in rough order: Prometheus, Sentry, Grafana, Snowflake / BigQuery / Postgres for SQL, GitLab, status page push.

### What phase 4 unlocks
- Firefight's own autonomous remediation (gated, approval-first)
- Day-one reality: "agent proposes rollback PR, waits for on-call approval, watches metrics for 10 min post-merge"
- End state vision: "alert fires at 3am, fixed before anyone wakes up"

Every team that has shipped this (Cleric, Aisera, Datadog Bits, PagerDuty AIOps) ships approval-first by design. The autonomous version is earned, not launched.

---

## Sequencing summary

| Phase | What ships | Time | What it sells as |
|---|---|---|---|
| 0 | Runbooks, Alert API + routing | Now (4-6 weeks) | "Modern incident platform" |
| 1 | Tool registry, prompt registry, agent run model, pgvector, AgentIncident v0 | Months 1-2 | "AI-native incident response on your team's data" |
| 2 | Extensible tool layer + bi-directional MCP (Firefight as MCP server) + GitHub + Datadog | Months 3-4.5 | "Plug anything in. Use Firefight from Claude Code." |
| 3 | Remediation primitives, safety engine, executable runbooks, long-running runtime, investigator agent | Months 5-6 | **"The open-source incident operations platform. Bring your own agent or use ours."** |
| 4 | Autonomous Firefight agent + demand-pulled connectors | Months 7-18+ | "Firefight fixes incidents before you wake up" |

Each phase is independently shippable and revenue-generating. Do not start phase N+1 before phase N has real users.

## What NOT to do
- Ship every integration ourselves. Build the framework; let customers and community fill the long tail.
- Unified observability query language across providers. Each keeps its own model.
- Per-vendor configuration UIs. Generic install UI parameterized per provider.
- Tinybird for analytics on day one. Postgres handles operational record fine.
- On-call scheduling vertical interleaved with phases 1-4. Separate product.
- MCP "in phase 4." MCP is the integration model itself, in phase 2, bi-directional.
- Ship the autonomous agent before the platform. Platform ships at month 6, agent on top.

## What CAN run in parallel
- Phase 0 runbooks and alerts (different workstreams, no dependencies)
- Within phase 1: prompt registry and agent run model
- Within phase 2: GitHub and Datadog as parallel dogfood once framework lands
- Within phase 2: MCP server adapter can be built alongside the consuming MCP client (same protocol, opposite direction)
- Within phase 3: safety engine and executable runbooks (different surface areas)
- Phase 4 connectors: one new first-party connector per engineer per cycle

## Open-source strategy as competitive lever
Two compounding effects unique to being open source:

1. **Community-contributed integrations**: every new MCP server in the world is a free Firefight integration. Every customer's internal tool can be upstreamed.
2. **Trust for production access**: customers connecting their production observability and infra to an AI agent need to see the code. Open source is the most direct answer to "can we trust this with prod?"

Both effects only work if the framework is genuinely good. Phase 2 has to be excellent.

The bi-directional MCP amplifies both:
- Claude Code and Cursor users discovering Firefight through their existing AI dev tools, then self-hosting
- Community publishing "Firefight + Claude Code" recipes on GitHub
- Customers' security teams reviewing the MCP server implementation as part of approving the integration

---

## Open questions to resolve before phase 1 kickoff

1. Embedding model choice and provider (Anthropic? OpenAI? Voyage? Self-hosted?). Cost / latency / vendor surface.
2. Should `AgentRun` be a subtype of `SolidWorkflow::Workflow` or its own model? Phase 1 fine standalone; phase 3's `DynamicAgentWorkflow` wants the substrate. Decide before committing schema.
3. Per-workspace prompt overrides: ship in phase 1 or defer? Recommend shipping schema, gating UI behind a flag.
4. Tool permission model: extend `ApiKey` with new scopes (`mcp`, `agent_invoke`, per-tool allow lists) or new agent-specific model? Likely extend `ApiKey` since the MCP server endpoint reuses it anyway.
5. Open-source license: MIT? Apache 2.0? AGPL? Affects fork behavior and willingness to upstream.
6. How much of `IncidentResponder` and `PostmortemGenerator` gets retrofitted onto the registry vs deprecated gradually?
7. MCP server: streamable HTTP transport from day one, or stdio-only first? Streamable HTTP is what Claude Code's remote-MCP support expects, so probably day one.
