# MCP Server

Firefight ships a [Model Context Protocol](https://modelcontextprotocol.io) server at `POST /mcp`, so any MCP client — Claude Code, Cursor, or your own agents — can query incidents, alerts, the service catalog, runbooks, and dry-run alert routing, and configure the workspace (catalog, routing rules, runbooks) with governed writes: every call flows through the Ability Gateway (grants → ledger → approval policies).

## Connecting

Mint a token under **Settings → API keys**:

- **Personal token** ("acts as you") — reads everything you can see, and writes whatever you can write, which for an admin is everything (`ApiKey#has_permission?` delegates to `WorkspaceMembership#implicitly_permits?` for a personal token, so the token inherits the human's reach exactly). For your own agent sessions.
- **Service key** scoped per resource and action — for headless agents and CI.

**Claude Code (OAuth — recommended)**

```sh
claude mcp add --transport http firefight https://<your-host>/mcp
```

On first use your browser opens Firefight's consent screen, which names the client and the workspace it would reach — click Authorize and you're connected. The client self-registers via dynamic client registration; tokens are short-lived with refresh rotation, PKCE (S256) is required, and you can revoke any connection under **Settings → API keys → Connected agents**.

A token belongs to exactly one workspace, because its Doorkeeper resource owner is a `WorkspaceMembership` — the same principal an `ApiKey` resolves to, which is what lets `Current.principal` stay a membership through the Ability Gateway, the ledger and the per-principal rate limit. Members of several workspaces pick one on the consent screen; the pick is resolved through the user's own memberships, so `workspace_id` cannot be forged. Reaching a second workspace means a second `claude mcp add` under a different name, with its own client and token.

The `initialize` instructions are built per request from `Current.workspace` and `Current.principal`, so the handshake names the workspace and who the connection acts as. An agent never needs a tool call to know where it is, and the answer cannot drift from the token — which is why there is no `get_workspace` tool.

**Claude Code (header token — for automation)**

```sh
claude mcp add --transport http firefight https://<your-host>/mcp \
  --header "Authorization: Bearer ff_..."
```

**Cursor** (`.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "firefight": {
      "url": "https://<your-host>/mcp",
      "headers": { "Authorization": "Bearer ff_..." }
    }
  }
}
```

Any other client: Streamable HTTP transport with either OAuth (discovery via `/.well-known/oauth-protected-resource`, RFC 7591 registration, PKCE required) or an `Authorization: Bearer` header token. Headless agents and CI should use header tokens — machines can't click consent screens.

## Read tools

| Tool | Answers |
|---|---|
| `search_incidents` | "What's open? What resolved this week?" — filters: status, severity, stage, text, time range |
| `get_incident` | "Tell me everything about INC-42" — detail, timeline, postmortem state, attached alerts, roles and their holders |
| `search_alerts` | "What's firing and how did it route?" — source, routing state, matched rule, incident link |
| `search_catalog` | "Who owns checkout?" — entries, attributes, relationships |
| `evaluate_routing` | "If this alert arrived, what would happen?" — matched rule, outcome, per-condition trace |
| `search_runbooks` | "Is there a runbook for this?" — incident response procedures by name/summary |
| `get_runbook` | "Walk me through the DB failover runbook" — full content and ordered steps |

Results are workspace-scoped to the token, capped at 50 items with explicit `truncated` markers, and returned as structured JSON.

## Config-write tools

| Tool | Does |
|---|---|
| `upsert_catalog_entry` | Create (no slug) or update (slug) a catalog entry with attributes |
| `delete_catalog_entry` | Soft-delete an entry by slug |
| `upsert_routing_rule` | Create or update an alert routing rule by priority — dry-run first with `evaluate_routing` |
| `delete_routing_rule` | Delete a rule by priority |
| `update_routing_config` | Grouping window + content match fields on the routing policy |
| `upsert_runbook` | Create or update a runbook (steps and attach conditions replace the existing set) |

Ids never leave the read tools, so every reference here resolves by slug too. `Mcp::ConditionValues` turns a condition into the row it needs: severity and incident type by slug, the custom field by its key, and values by option label or catalog entry slug. Anything matching no record raises rather than storing a condition that saves cleanly and then never fires. `CatalogEntry::ReferenceManagement` resolves reference attributes the same way, guarding the id lookup so a slug reaching a uuid column cannot raise out of the driver.

## Incident-write tools

| Tool | Does |
|---|---|
| `assign_incident_role` | Assign one person to an incident role, or clear it (omit `member`) |
| `attach_runbook` | Attach a runbook to an incident by slug, idempotent |

`assign_incident_role` authorizes as `incidents:update`. Roles hold one person each, so assigning replaces the current holder; the Incident Lead cannot be cleared, only handed over. `get_incident` returns every configured role with its holder, which is how an agent discovers the slugs it may pass. The rest of the incident lifecycle (declare, status, severity, close) stays out of MCP for now.

Authorization is the gateway's: admin personal tokens carry the admin's authority; service keys need the explicit `<resource>:<action>` scope. Every write is ledgered (`AbilityInvocation`), and workspace approval policies can park any call as `pending` — the tool result then carries an `approval id`; after a workspace admin approves (Slack buttons or `/app/gateway/approvals`), retry the identical call with `approval_id`.

The server is self-describing for agents: server instructions, tool descriptions, and guidance-worthy responses (permission errors, no routing policy, unmatched dry runs) link to the relevant public docs page via `Mcp::Docs` constants — each page is fetchable as raw markdown (`https://firefight.app/docs/**/*.md`, index at `/llms.txt`).

## Architecture

`McpController` (entry point: Bearer auth → `Current.principal`, API rate limit, stateless `handle_json` dispatch — no sessions/SSE, multi-worker safe) → `Mcp::ToolDispatcher` (telemetry; routes every call through `AbilityGateway.authorize!`, which resolves the principal's grants and ledgers denials) → tool classes in `app/mcp/` (workspace-scoped reads + formatting only; no business logic, no writes, no adapter calls; tool names from `Mcp::Tools` constants).

Each tool declares what it authorizes as (`authorize_as`, or `upserts`, which splits create vs update by whether the slug resolves and turns a slug that resolves to nothing into "Not found in this workspace." rather than a silent duplicate). Personal tokens resolve to the human: members pass every read plus `incidents.create`/`incidents.update`, admins pass every write. Service keys need the explicit `<resource>:<action>` scope, drawn from `Ability::Action::RESOURCES`: `incidents`, `alerts`, `catalog`, `policies` for routing, `runbooks`, `approvals`, `custom_fields` for field definitions and `forms` for what a lifecycle form asks.

**The API key screen must offer every resource and action.** It once mirrored the `/api/v1` routes alone, which left thirteen of the twenty tools ungrantable to a service key: `runbooks` and `approvals` had no row at all, and `custom_fields` offered only read. The effect was that an agent could not be scoped, it had to run as an admin human over OAuth and inherit everything, which is the reverse of the rule that machines never inherit a human's reach. `permissions-matrix.tsx` now renders `Ability::Action::RESOURCES` × `Ability::Action::ACTIONS` in full.

Adding a resource means adding the `Ability::Action` rows for it. `Ability::Action.lookup` returning nil denies **everyone**, admins included, so a new resource needs a migration calling `sync_system_actions!` and not just a seeds run.
