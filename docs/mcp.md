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

## Choices come from the workspace

A parameter whose values are the workspace's own is declared on the tool with `choice :role, from: ->(workspace) { ... }`, and a parameter naming a person with `person :member`. `Base.schema_for(workspace)` fills the choices into the parameter description at the moment the tool is offered ("one of: incident_lead (Incident Lead), ..."), and says a person parameter takes `"me"`. The agent's wrapper and the MCP server (`Mcp::Tools.for_workspace`, `Mcp::WorkspaceTool`) both hand out that schema, so a model picks from what exists rather than guessing a name, and an outside client sees the same. `WorkspaceMembership.resolve!(reference, acting:)` turns `"me"` into whoever is acting, and refuses it when a machine is acting, since a key has no seat in an incident.

## Read tools

| Tool | Answers |
|---|---|
| `search_incidents` | "What's open? What resolved this week?" — filters: status, severity, stage, text, time range |
| `get_incident` | "Tell me everything about INC-42" — detail, timeline, postmortem state, attached alerts, roles and their holders |
| `search_similar` | "Has this happened before?" — incidents, postmortems and findings nearest by meaning (`SearchEmbeddingService`, pgvector), findings only when the caller may read investigations |
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
| `search_activity` | The invocation ledger, filtered by decision and ability key. A tool's row names the connection it ran through as a person tells it apart (`connection`, such as "Faylee (Northflank)") and its `provider` |
| `search_approvals` | Approvals by status, each with its ability key and, for a tool, the connection it runs through (`connection`) and its `provider`, so a pending request says which account it would reach |

## Incident-write tools

| Tool | Does |
|---|---|
| `assign_incident_role` | Assign one person to an incident role, or clear it (omit `member`) |
| `attach_runbook` | Attach a runbook to an incident by slug, idempotent |
| `dismiss_timeline_note` | Dismiss one AI-noted milestone from an incident's timeline by id |
| `declare_incident` | Open an incident against the workspace's Declare form |
| `post_incident_update` | Post an update against the Update form |
| `resolve_incident` / `cancel_incident` / `reopen_incident` | Move an incident through its lifecycle. On the update, resolve and cancel forms a required answer left out takes the incident's current value (`IncidentFormPrompt#answers_with_current`), the same prefill the Slack modal and the dashboard give a person, and only a value the field would offer counts, so a resolve with two closed statuses still asks which. `get_form` marks a field the resolver will not ask right now with `asked: false` and its `inactive_reason` |
| `create_action_item` | Add a piece of work and post it to the channel |
| `assign_action_item` | Take a piece of work, or hand it to someone (omit `member` to take it) |
| `complete_action_item` | Mark a piece of work done |
| `rename_action_item` / `reopen_action_item` / `unassign_action_item` | Change what a piece of work says, open a done one again, or let go of it so nobody holds it |
| `create_action_item_issue` | Open a piece of work's issue in the workspace's issue tracker, or try again after it failed |
| `claim_runbook_step` | Take one step of an attached runbook, creating the item behind it |
| `link_incident` | Record a `related` link, or a `duplicate` that cancels this incident into the other |
| `escalate_incident` | Ask a named person to pick the incident up, with a DM and a chase |
| `invite_responders` | Bring people into the incident channel |
| `give_shoutout` | Thank someone for their work, posted in the channel |

**Participation is the point.** An agent that can open and close an incident but cannot raise work, take it, pull a human in or say what it found is a reporting tool, not a responder. Each of these calls the same service the Slack button and the dashboard call, so an item raised over MCP is indistinguishable from one raised by a person, and the timeline names the agent rather than whoever created its token.

`get_incident` returns `action_items` and `runbooks` with their ids, which is where an agent gets the ids these tools take. Without them the work would be visible and unnameable. An item that tracks an issue carries its `external_key` and `external_url`, and `issue_status` when its issue is missing or not kept in step. `create_action_item_issue` opens an item's issue in the workspace's tracker, the "Create issue" button, made as Firefight issue sync with the caller named in the activity log, and is refused with the reason when the item has one or the workspace opens none. Each timeline entry for an update or a cancellation carries `update`, the message the responder posted and the fields it changed with their before and after.

`assign_action_item` and `claim_runbook_step` take the work themselves when `member` is omitted, which is the "I can take this" button. Naming someone else announces the handover, the way Slack does. `escalate_incident` and `invite_responders` differ on purpose: inviting lets people watch, escalating asks one named person to answer and chases them if they do not.

An agent can hold work. `incident_actions.created_by` and `assignee` are polymorphic, as `declared_by` is, so an item can belong to an `Agent` or a service key. A machine has no Slack account to mention, so `Slack::Mrkdwn.mention` names it in bold rather than rendering an empty `<@>`, and the dashboard marks it with a robot rather than a person's initials.

`dismiss_timeline_note` also authorizes as `incidents:update`. It is error correction on the notes Firefight reads out of the channel transcript when an incident ends, described in [ai.md](ai.md). A joke read as a decision, or the wrong person credited. The note is kept and marked dismissed rather than deleted, and stops being returned in `get_incident`'s timeline. Note ids come from that timeline, where each `milestone.noted` entry also carries its `kind`.

`assign_incident_role` authorizes as `incidents:update`. Roles hold one person each, so assigning replaces the current holder; the Incident Lead cannot be cleared, only handed over. `get_incident` returns every configured role with its holder, which is how an agent discovers the slugs it may pass.

Authorization is the gateway's: admin personal tokens carry the admin's authority; service keys need the explicit `<resource>:<action>` scope. Every write is ledgered (`AbilityInvocation`), and workspace approval policies can park any call as `pending` — the tool result then carries an `approval id`; after a workspace admin approves (Slack buttons or `/app/gateway/approvals`), retry the identical call with `approval_id`.

The server is self-describing for agents: server instructions, tool descriptions, and guidance-worthy responses (permission errors, no routing policy, unmatched dry runs) link to the relevant public docs page via `Mcp::Docs` constants — each page is fetchable as raw markdown (`https://firefight.app/docs/**/*.md`, index at `/llms.txt`).

## Halon, the agent

Three tools put Halon in front of an outside agent, such as one in a person's editor. All three go through the gateway as whoever the credential resolves to: a personal token as the person, an agent token as the agent, a service key as itself.

| Tool | Does | Permission |
|---|---|---|
| `start_investigation` | Starts a run on an incident (`Investigation::TRIGGER_MCP`), or on a problem with no incident when `symptom` says what is wrong, with a brief: what is failing, roughly when it started, names and error text (`Investigation::Brief::SCHEMA`, the same fields the chat hands over). One live run per incident, a second request is told which one is running. | `investigations: create` |
| `get_investigation` | One run by id, or an incident's newest: status, theories with the steps behind them, every step's label and status, the finding with each claim, its step numbers and its sources. Never a step's raw output, never a technical failure cause, which stays in `error_summary` for debugging. | `investigations: read` |
| `get_halon_performance` | How Halon has done over 7, 30 or 90 days (30 by default): runs, answers and the median time to one, what the team said of the answers (right, partly right, wrong, not rated), what came of its fixes, and the answers marked wrong with the cause they gave and the lessons from their incident. Rehearsals are left out. | `investigations: read` |
| `ask_halon` | One chat turn, synchronously, and the answer. The chat is a `Conversation` of `KIND_MCP`, one per principal (`Conversation.for_mcp!`), so questions carry on. Delivery is `Conversation::QuietDelivery`, nothing streams. A turn that pauses on a confirmation returns `status: waiting` with the questions in the words the dashboard shows, since an MCP call has no Confirm button. A call through a connection is asked about what the tool reaches, such as "Api request on Faylee (Northflank), project faylee?", never in the agent's words (docs/ai.md). | `investigations: create` |

Every member holds `investigations: create` without a grant until an admin narrows it (docs/integrations.md, A default a grant narrows), so a personal token or OAuth connection can call `ask_halon` and `start_investigation` from the start, and a service key or agent needs a grant. `ask_halon` and `start_investigation` are never offered to Halon itself (`Chat::Tools::Groups::NOT_FOR_HALON`). `get_investigation` and `get_halon_performance` are, under Incidents and what happened before. A conversation's `started_by` is polymorphic for this, the same shape as `Investigation#triggered_by`.

## Configuring the workspace

Everything a person can change on a settings screen has a tool, because the
surface should not decide who is holding the key. An SRE in Claude Code saying
"go set our severities up" and an agent doing the same thing are the same call,
and the gateway is what tells them apart.

| Tool | Manages |
|---|---|
| `get_workspace_config` | One read behind all of it: severities, statuses with their stage, types, roles, alert sources, webhooks and the workspace settings |
| `list_integrations` | What can be connected and where each provider stands, by registry category (`IntegrationProvider.card_for`). Without a category, one line per category with what is connected in it. `integrations: read`. In the dashboard chat a category's answer is drawn as a card, see docs/ai.md. It never connects anything, since OAuth and keys belong in the connect dialog |
| `get_resource_map` | The first place to find which provider and account hold a named resource, and its description opens by saying so, before asking a person or using a provider's own tools. The resource map (`ResourceMap`), read off the workspace's connections, Cloudflare's zones, hostnames, Workers, storage, tunnels, load balancers and Access applications included. Without a resource, every present resource one line each, grouped by provider and account, and each swept connection's last sweep, error and gaps, while fewer than 300 are visible (`MAP_LINES`). From 300 it is the map's numbers instead (`summary`): counts by provider, kind, environment and health (`ResourceMap::Stats`), the ten most depended on (`ResourceMap::Query`, sorted by dependents), the same connection lines, and one sentence naming the total and pointing at `find_resources`, `traverse_resource_map` and `blast_radius`, so a list is never cut short without saying so. With a resource (`ResourceMap::Resource.referenced`, by name, provider id or its id on the map), up to five fact sheets: where it runs, its environment, page, details, first and last seen, the catalog services it runs with what each is for and who owns it, what people confirmed about it, the last five incidents on those services with how each ended, what normal looks like for its metrics over the last week (`normal`, from `ResourceMap::Baseline`), the patterns it usually logs (`usual_log_lines`, the ten with the most lines, or why none are known, `ResourceMap::LogTemplate`), its key checks (`key_checks`, one line each: the check, the read it runs as, the connection that answers and its normal, or why it cannot run here, or why the kind has none, `ResourceMap::KeyQueries`), and every link within two hops (`Resource#neighborhood`), each saying how it was found, with the names of the settings it was found in ("matched from web's DATABASE_URL setting, which names its address", never a value), a suggestion marked not confirmed. Only what the caller reads (`ResourceMap::Resource.visible_to`, docs/integrations.md, Who reads the map): a resource outside its environments is absent from the list, naming one answers as for a name not on the map, a connection row outside them is left out of the sweeps, and a sheet leaves out a link to such a resource and only counts it (`out_of_reach`). `map: read` |
| `search_map` | One search across the map, the catalog and confirmed memories, ranked together (`SearchDocument.search`, through `MapSearchService`, docs/integrations.md, Searching the map). `query` is required. `types` picks `resource`, `catalog_entry` and `memory`, all three by default and resources alone when a `find_resources` filter is given, and the filters are those (`Mcp::Tools::MapFilters`). An exact name, provider id, slug or account comes first, then the rest by reciprocal rank fusion of words (a prefix of each), fragments and misspellings of a name or id (trigrams), what a catalog entry's description means (its embedding, when the workspace has AI) and words of a confirmed memory. `limit` defaults to 25, at most 50, and `next_cursor` is tied to the query, types and filters, refused with the reason otherwise. Each result is its type, id, title, why it matched, a resource's kind, provider, account, environment and status or an entry's catalog type, slug and description or a memory's subject and who confirmed it, and `link`, the dashboard page that opens it. Each type is searched only when the caller may read it, resources through `ResourceMap::Resource.visible_to`, the catalog with `catalog: read` and memories with `memory: read` while Halon is available, and `not_searched` names the types it could not search. `map: read` |
| `find_resources` | Resources by filter, a page at a time (`ResourceMap::Query`): provider, kind, account, environment (by slug or name, the workspace's environments listed as its choices), status, health, `owner` (a team by name, slug or id), `catalog_entry` (any entry by name, slug or id), `tag` (`key` or `key=value`), `field` (exact details), `name_starts_with`, `changed_since` and `include_removed`, sorted by name or by dependents. `limit` defaults to 50, at most 200, and `next_cursor` is the query's opaque keyset cursor, refused with the reason when it is not one a page gave or belongs to the other sort. Each row is the resource's id, name, kind, provider, account, environment, status, health and direct dependents, and `total` stops counting at 10,000 (`10,000+`). A team, entry or environment the catalog does not hold is refused rather than read as no filter (`Mcp::Tools::MapFilters`, through `CatalogEntry.referenced`). `map: read` |
| `get_resource` | One resource's fact sheet, `get_resource_map`'s without the two hop walk, with `id` its id on the map, `provider_id`, `health`, and its standing links counted by relation each way (`links_out`, `links_in`), unconfirmed suggestions counted apart and links to resources outside the reader's environments only counted. `map: read` |
| `get_resource_links` | One resource's links, `in`, `out` or `both`, by `relations` and `origins` (`facts`, `suggestions` or `all`), 100 a page and at most 500, by cursor. Each is its sentence, relation, origin, how it was found (the fact sheet's words, `GetResourceMap.how_found`), whether a suggestion was confirmed, its certainty, clues and note, `settings` (the names of the settings it was found in, such as `DATABASE_URL`, never their values) and the other end's id. `map: read` |
| `get_resource_neighbours` | The resources one link away each way (`depends_on`, `dependents`), grouped by relation, as `find_resources` rows. Facts unless `include_suggestions`, and the unconfirmed suggestions it left out are counted. At most 200, then how many more. `map: read` |
| `traverse_resource_map` | A walk from one resource (`ResourceMap::Graph`), `depends_on` or `dependents`, 1 to 6 hops (2 by default), by `relations` (the runtime ones by default) and `kinds` (listed only, the walk goes through others), facts unless `include_suggestions`. Each resource reached is a row with its `hop` and `via`, the link it was reached by from one a hop nearer. At most 200, nearest first, then how many more were reached. `map: read` |
| `blast_radius` | What fails with a resource (`ResourceMap::BlastRadius`, which takes `hops`), 10 hops by default and at most: dependents counted by kind, provider and environment, the catalog services they and the resource run with their owners and open incidents, those incidents, and the 25 dependents most others rely on. What unconfirmed suggestions would add is counted apart and listed only with `include_suggestions`. `map: read` |
| `resource_map_stats` | `ResourceMap::Stats` by `group_by` (provider, kind, account, environment, status or health) under `find_resources`' filters, with each connection's last sweep, error and gaps, the suggestions waiting on a person and the last day's changes by kind. `map: read` |
| `search_logs`, `query_metrics`, `recent_deploys`, `resource_status`, `search_errors`, `search_traces`, `rollback`, `restart`, `scale` | Capabilities for anything on the resource map (`Mcp::CapabilityToolFactory`, docs/integrations.md, Capabilities). Each takes `resource`, by its name, its provider's id or its id on the map, and `connection` when more than one connection could answer, listing every connection whose provider answers the capability with its tools on or not (one whose tool is off answers that it is), finds the resource only among what the principal reads on the map, resolves to a provider tool the principal may run on a connection that runs or watches it (an observability tool answers logs, metrics, traces and errors by default, and the platform answers in the same call when it has no answer, the response saying so), and is authorized, approved and ledgered as that tool's action with its own arguments. A read takes `connection: all`, which asks each connection in its own authorized call and returns every answer headed with its connection, structured answers keyed by connection, an error only when all failed. A call there that waits for approval is retried alone, naming its connection. Listed only when some switched on tool could answer it and the principal may call one of them, beside the provider tools themselves. | The provider tool's action |
| `run_key_query` | One of a resource's key checks (`ResourceMap::KeyQueries`, docs/integrations.md, Key checks): `resource`, `query` (the check, such as `error_rate`, `latency_p95` or `throttles`) and `minutes`. The check names the capability and arguments it runs, and the first of its metrics the connection keeps is read, so it is routed, authorized, approved and ledgered exactly as that capability's call (`CapabilityToolFactory.answer`, falling back to the platform as the capability does). The answer starts with a line saying what was checked, through which connection, and how the reading compares with the normal that connection read (`3.1x the usual high`), then the capability's own answer. A check the kind does not have is refused with the ones it has. Listed when the principal may call a capability a check reads through. | The provider tool's action |
| `new_log_patterns` | A resource's recent logs, `resource` and `minutes` (60 by default), read through the logs capability with up to 2,000 lines, so it is routed, authorized, approved and ledgered as that capability's call (`CapabilityToolFactory.answer`). The lines are mined into patterns (`ResourceMap::LogMiner`) and set against the patterns the resource printed in the last week (`ResourceMap::LogTemplate.compare`). The answer is the patterns not seen in the last week, most lines first, and the error patterns that are usual, never the raw lines. Listed when the principal may call the logs capability. | The provider tool's action |
| `suggest_resource_link` | A link between two resources on the map that no provider declares, with the evidence, as a suggestion (`ResourceMap::Link.suggest!`). It shows dashed until a person confirms or dismisses it on the map page. A pair already linked, or a suggestion already dismissed, is refused with the reason. Resources are named by their name, their provider's id or their id on the map, and a name two resources share lists each one's map id and the connection it is on. `catalog: update` |
| `update_workspace_settings` | The settings under Settings, Workspace: transcript access, transcript retention, the channel archive delay, web search, testing Halon on rated answers, and which connected coding agent writes code fixes (`code_fix_agent`, a connection slug, or null for Firefight's own agent). `workspace: update`, admin-only. Annotated destructive, so a chat asks before any of them, since they are workspace wide and an ordinary update verb would not ask. Also which issue tracker items are kept in step with (`issue_tracker`), when a new item gets an issue (`issue_creation`), where issues go (`issue_tracker_target`, by the tracker's own fields) and its webhook's signing secret (`issue_webhook_secret`, never read back) |
| `upsert_severity` / `delete_severity` | Severities. `position` says how severe, 1 being the most, and `rank` in the response is derived from it |
| `upsert_status` / `delete_status` | Statuses, with `lifecycle_stage` |
| `upsert_incident_type` / `delete_incident_type` | Incident types |
| `upsert_incident_role` / `delete_incident_role` | Incident roles |
| `upsert_alert_source` / `delete_alert_source` | Alert sources, addressed by endpoint path |
| `upsert_webhook` / `delete_webhook` | Outbound webhooks |
| `test_webhook` | Queues a test delivery to a webhook: the newest subscribed event, signed as a live one. `Webhook#queue_test_delivery!` is the one home for it, and `test_blocked_reason` for why it cannot send, so the dashboard button and the tool refuse identically |
| `list_agents`, `upsert_agent`, `rotate_agent_token`, `revoke_agent_token`, `delete_agent` | Agents and their credentials |
| `list_api_keys`, `upsert_api_key`, `delete_api_key` | Service keys |

**The map tools read alike.** `get_resource_map`, `search_map`, `find_resources`, `get_resource`, `get_resource_links`, `get_resource_neighbours`, `traverse_resource_map`, `blast_radius` and `resource_map_stats` all authorize as `map: read`, only read, and pass `within: ResourceMap::Resource.visible_to(principal, workspace)` to the query layer, so a narrowed reader is never shown, counted or walked through a resource outside its environments, and a link out of its reach is at most counted. A resource is named by its name, its provider's id or its id on the map (`ResourceMap::Resource.referenced`, which tries the id only for a value shaped like one), a present one is chosen over one gone from its connection, and a name several share answers with each candidate's row rather than a guess (`Mcp::Tools::MapPayloads#locate`). Naming a resource the reader cannot see answers exactly as naming nothing. Every tool answers in the same row (`MapPayloads#row`) and the same link sentence and how it was found as the fact sheet, so a resource reads the same whichever tool found it. Halon has them in a group of their own, see docs/ai.md.

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
positions gapless, and `#place_at!` owns moving one row through that same
renumber. Every list takes `position` on create and update, on MCP and on
REST. A severity's `rank` is derived from position by the reorder (first in the
list gets the highest rank) and is never accepted as input: writing it directly
skipped the renumber, so a new row's rank was overwritten on create and an
update could leave two severities sharing one rank. and `disable!`, `make_default!` and `destroy_from_list!`
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

Each tool declares what it authorizes as (`authorize_as`, or `upserts`, which splits create vs update by whether the slug resolves and turns a slug that resolves to nothing into "Not found in this workspace." rather than a silent duplicate). Personal tokens resolve to the human: members pass every read plus `incidents.create`/`incidents.update` and `chats.update`/`chats.delete` for their own chats, admins pass every write. A member's `map.read` is every environment until a grant narrows it, and reads through the token the same way. Service keys need the explicit `<resource>:<action>` scope, drawn from `Ability::Action::RESOURCES`: `incidents`, `alerts`, `catalog`, `policies` for routing, `runbooks`, `approvals`, `custom_fields` for field definitions and `forms` for what a lifecycle form asks.

**The API key screen must offer every resource and action.** It once mirrored the `/api/v1` routes alone, which left thirteen of the twenty tools ungrantable to a service key: `runbooks` and `approvals` had no row at all, and `custom_fields` offered only read. The effect was that an agent could not be scoped, it had to run as an admin human over OAuth and inherit everything, which is the reverse of the rule that machines never inherit a human's reach. `permissions-matrix.tsx` now renders every grantable resource with the actions it offers (`Ability::Action.actions_for`, exported as `ABILITY_RESOURCE_ACTIONS`). `map` offers only read, so its other cells are a plain hyphen.

Adding a resource means adding the `Ability::Action` rows for it. `Ability::Action.lookup` returning nil denies **everyone**, admins included, so a new resource needs a migration calling `sync_system_actions!` and not just a seeds run.
