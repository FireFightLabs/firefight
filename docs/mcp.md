# MCP Server

Firefight ships a [Model Context Protocol](https://modelcontextprotocol.io) server at `POST /mcp`, so any MCP client — Claude Code, Cursor, or your own agents — can query incidents, alerts, the service catalog, runbooks, and dry-run alert routing, and configure the workspace (catalog, routing rules, runbooks) with governed writes: every call flows through the Ability Gateway (grants → ledger → approval policies).

## Connecting

Three kinds of credential, by who the call should be attributed to:

- **Agent token**, minted under **Gateway → Agents** — the call is attributed to the agent itself. `ApiKey#principal` returns `agent || on_behalf_of || self`, so the agent is what the gateway authorizes, what the ledger records, and what `declared_by` and every timeline `actor` name. For an AI that takes part in incidents under its own name.
- **Personal token** ("acts as you"), under **Developer → API Keys** — reads everything you can see, and writes whatever you can write, which for an admin is everything (`ApiKey#has_permission?` delegates to `WorkspaceMembership#implicitly_permits?` for a personal token, so the token inherits the human's reach exactly). For your own sessions.
- **Service key** scoped per resource and action, under **Developer → API Keys** — for headless integrations and CI, attributed to the key.

**Agent tokens are long-lived on purpose.** There is no refresh flow: an agent runs unattended, and what a leaked token can do is bounded by the agent's grants, the approval rules that park its risky calls, and the ledger that records every one, not by an expiry it would have to renew through a flow nobody is present for. The OAuth refresh path below is for third-party clients borrowing a person's authority, which is a different problem. Rotation is an overlap rather than a swap: **Issue a new token** mints a second live credential, the agent keeps running on the old one until its config is updated, and **Tokens → Revoke** ends the old one. Grants and history hang off the agent, so neither moves.

**Claude Code (OAuth — recommended)**

```sh
claude mcp add --transport http firefight https://<your-host>/mcp
```

On first use your browser opens Firefight's consent screen, which names the client and the workspace it would reach — click Authorize and you're connected. The client self-registers via dynamic client registration; tokens are short-lived with refresh rotation, PKCE (S256) is required, and you can revoke any connection under **Developer → API Keys → Connected agents**.

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

## Gateway tools

The Ability Gateway is administered over MCP with the same model calls the dashboard and REST API use (`Ability::Principal`, `Ability::Grant.grant!`, `Ability::Role#sync_actions!`, `PolicyRule::ApprovalRuleChanges`). All of them authorize as `permissions:*`, which is admin-only and ungrantable, so only an admin's personal token or OAuth session can reach them. `Mcp::Tools::GatewayPayloads` keeps the grant, set and rule shapes identical across the tools.

| Tool | Does |
|---|---|
| `list_abilities` | Every grantable ability with risk level, group and whether approval rules can hold it |
| `list_principals` | People, agents and service keys with the grants each holds |
| `upsert_permission_set` | Create (no slug) or update (slug) a set. `abilities` is the full contents |
| `delete_permission_set` | Delete a set, revoking it from everyone holding it |
| `grant_ability` | Grant an ability key or a set slug to a principal, with environment slugs and an expiry. Regranting retargets the existing row |
| `revoke_grant` | Revoke a grant by id |
| `upsert_approval_rule` | Create (no id) or update (id) an approval rule. Only the keys given change |
| `delete_approval_rule` | Delete a rule by id |
| `search_activity` | The invocation ledger, filtered by decision and ability key |

## Incident-write tools

| Tool | Does |
|---|---|
| `assign_incident_role` | Assign one person to an incident role, or clear it (omit `member`) |
| `attach_runbook` | Attach a runbook to an incident by slug, idempotent |
| `dismiss_timeline_note` | Dismiss one AI-noted milestone from an incident's timeline by id |
| `declare_incident` | Open an incident against the workspace's Declare form |
| `post_incident_update` | Post an update against the Update form |
| `resolve_incident` / `cancel_incident` / `reopen_incident` | Move an incident through its lifecycle |
| `create_action_item` | Add a piece of work and post it to the channel |
| `assign_action_item` | Take a piece of work, or hand it to someone (omit `member` to take it) |
| `complete_action_item` | Mark a piece of work done |
| `claim_runbook_step` | Take one step of an attached runbook, creating the item behind it |
| `link_incident` | Record a `related` link, or a `duplicate` that cancels this incident into the other |
| `escalate_incident` | Ask a named person to pick the incident up, with a DM and a chase |
| `invite_responders` | Bring people into the incident channel |
| `give_shoutout` | Thank someone for their work, posted in the channel |

**Participation is the point.** An agent that can open and close an incident but cannot raise work, take it, pull a human in or say what it found is a reporting tool, not a responder. Each of these calls the same service the Slack button and the dashboard call, so an item raised over MCP is indistinguishable from one raised by a person, and the timeline names the agent rather than whoever created its token.

`get_incident` returns `action_items` and `runbooks` with their ids, which is where an agent gets the ids these tools take. Without them the work would be visible and unnameable.

`assign_action_item` and `claim_runbook_step` take the work themselves when `member` is omitted, which is the "I can take this" button. Naming someone else announces the handover, the way Slack does. `escalate_incident` and `invite_responders` differ on purpose: inviting lets people watch, escalating asks one named person to answer and chases them if they do not.

An agent can hold work. `incident_actions.created_by` and `assignee` are polymorphic, as `declared_by` is, so an item can belong to an `Agent` or a service key. A machine has no Slack account to mention, so `Slack::Mrkdwn.mention` names it in bold rather than rendering an empty `<@>`, and the dashboard marks it with a robot rather than a person's initials.

`dismiss_timeline_note` also authorizes as `incidents:update`. It is error correction on the notes Firefight reads out of the channel transcript when an incident ends, described in [ai.md](ai.md). A joke read as a decision, or the wrong person credited. The note is kept and marked dismissed rather than deleted, and stops being returned in `get_incident`'s timeline. Note ids come from that timeline, where each `milestone.noted` entry also carries its `kind`.

`assign_incident_role` authorizes as `incidents:update`. Roles hold one person each, so assigning replaces the current holder; the Incident Lead cannot be cleared, only handed over. `get_incident` returns every configured role with its holder, which is how an agent discovers the slugs it may pass.

Authorization is the gateway's: admin personal tokens carry the admin's authority; service keys need the explicit `<resource>:<action>` scope. Every write is ledgered (`AbilityInvocation`), and workspace approval policies can park any call as `pending` — the tool result then carries an `approval id`; after a workspace admin approves (Slack buttons or `/app/gateway/approvals`), retry the identical call with `approval_id`.

The server is self-describing for agents: server instructions, tool descriptions, and guidance-worthy responses (permission errors, no routing policy, unmatched dry runs) link to the relevant public docs page via `Mcp::Docs` constants — each page is fetchable as raw markdown (`https://firefight.app/docs/**/*.md`, index at `/llms.txt`).

## Configuring the workspace

Everything a person can change on a settings screen has a tool, because the
surface should not decide who is holding the key. An SRE in Claude Code saying
"go set our severities up" and an agent doing the same thing are the same call,
and the gateway is what tells them apart.

| Tool | Manages |
|---|---|
| `get_workspace_config` | One read behind all of it: severities, statuses with their stage, types, roles, alert sources and webhooks |
| `upsert_severity` / `delete_severity` | Severities, with `rank` |
| `upsert_status` / `delete_status` | Statuses, with `lifecycle_stage` |
| `upsert_incident_type` / `delete_incident_type` | Incident types |
| `upsert_incident_role` / `delete_incident_role` | Incident roles |
| `upsert_alert_source` / `delete_alert_source` | Alert sources, addressed by endpoint path |
| `upsert_webhook` / `delete_webhook` | Outbound webhooks |
| `list_agents`, `upsert_agent`, `rotate_agent_token`, `revoke_agent_token`, `delete_agent` | Agents and their credentials |
| `list_api_keys`, `upsert_api_key`, `delete_api_key` | Service keys |

**The four option lists share their operations and not their payloads**, which
is why they are eight tools rather than one with a `kind` argument. A status
needs a lifecycle stage, a severity needs a rank, and only some are colored or
defaultable. One schema carrying all four conditionally would leave an agent
guessing which apply, so `ConfiguresOption` shares the implementation and each
tool declares its own fields. `configures_option` takes the model, the gateway
resource, the `extra` schema properties this list has, and a `prepare` lambda
saying how those arguments land as attributes.

**One home per rule.** `ConfigurableOption.create_in_list!` and
`#destroy_from_list!` own creating and deleting with the renumber that keeps
positions gapless, and `disable!`, `make_default!` and `destroy_from_list!`
raise `OptionGuards::Blocked` when a `*_blocked_reason` refuses. The dashboard,
MCP and REST all call the same methods, so a rule cannot be enforced on one
surface and forgotten on another. The dashboard still pre-checks so it can name
the rule on a control it should not have offered, and rescues the same error for
the race where two people act at once.

**Postmortems.** `get_postmortem`, `start_postmortem`, `update_postmortem` and `set_postmortem_status` close the loop an agent could otherwise not: it could declare, work and resolve an incident and then not write it up. `Incident#postmortem_blocked_reason` is the one home for when a write-up is possible, so the dashboard, MCP and REST all refuse a still-open or canceled incident with the same sentence. `postmortems.generated_by` is polymorphic, so an agent is recorded as the author. `update_postmortem` replaces the body rather than appending, and the HTML is sanitised down to what the editor allows.

`PostmortemGenerationJob` takes only an incident id now. The postmortem already records who started it, and the old second argument could not name an agent at all.

**Credentials are admin-only and ungrantable.** `upsert_agent`, `upsert_api_key`
and their siblings authorize as `permissions` and `api_keys`, both in
`ADMIN_ONLY_RESOURCES`. An admin's personal token or OAuth session reaches them
and no service key or agent ever can, whatever it was granted, so an agent
cannot mint another agent. Creating one returns its token once and never again,
and a listing never carries one.

## Reading the conversation

`get_incident_transcript` returns what people actually said in an incident
channel, in order, with who said it. It is the one thing `get_incident` never
gave an agent: the timeline says what happened, the transcript says why.

It authorizes as `incident_transcripts`, deliberately not `incidents`, so a key
already granted incidents does not silently gain the conversation. It also
refuses unless the workspace has turned transcript access on. See the gates and
the retention window in [ai.md](ai.md).

Paging walks backwards from the end, since the last thing said is usually the
part worth reading, and `more_before` carries the cursor. The limit is capped at
500 rather than trusted.

## Architecture

`McpController` (entry point: Bearer auth → `Current.principal`, API rate limit, stateless `handle_json` dispatch — no sessions/SSE, multi-worker safe) → `Mcp::ToolDispatcher` (telemetry; routes every call through `AbilityGateway.authorize!`, which resolves the principal's grants and ledgers denials) → tool classes in `app/mcp/` (workspace-scoped reads + formatting only; no business logic, no writes, no adapter calls; tool names from `Mcp::Tools` constants).

Each tool declares what it authorizes as (`authorize_as`, or `upserts`, which splits create vs update by whether the slug resolves and turns a slug that resolves to nothing into "Not found in this workspace." rather than a silent duplicate). Personal tokens resolve to the human: members pass every read plus `incidents.create`/`incidents.update`, admins pass every write. Service keys need the explicit `<resource>:<action>` scope, drawn from `Ability::Action::RESOURCES`: `incidents`, `alerts`, `catalog`, `policies` for routing, `runbooks`, `approvals`, `custom_fields` for field definitions and `forms` for what a lifecycle form asks.

**The API key screen must offer every resource and action.** It once mirrored the `/api/v1` routes alone, which left thirteen of the twenty tools ungrantable to a service key: `runbooks` and `approvals` had no row at all, and `custom_fields` offered only read. The effect was that an agent could not be scoped, it had to run as an admin human over OAuth and inherit everything, which is the reverse of the rule that machines never inherit a human's reach. `permissions-matrix.tsx` now renders `Ability::Action::RESOURCES` × `Ability::Action::ACTIONS` in full.

Adding a resource means adding the `Ability::Action` rows for it. `Ability::Action.lookup` returning nil denies **everyone**, admins included, so a new resource needs a migration calling `sync_system_actions!` and not just a seeds run.
