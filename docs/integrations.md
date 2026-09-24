# Integrations & the Ability Gateway

One system seen from two ends. **Connections mint abilities; the gateway authorizes every use of one.** Enabling a capability on a connection card creates exactly one permissioned action, and from that moment it is grantable, approvable, and ledgered like anything else in the product.

## The chokepoint

Every privileged operation goes through one method:

```ruby
AbilityGateway.authorize!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {}) { execute }
```

API controllers, MCP dispatch, Slack dispatch, and connection tools all route here. **Never check permissions inline** anywhere else; the convergence is the safety property. Each entry point has exactly one gate, at its own dispatcher: `Api::V1::ApiController#authorize!`, `Mcp::ToolDispatcher`, and `AuthorizedDispatch` for `CommandDispatcher`/`InteractionDispatcher`. The gate stays at the entry point rather than moving down into the services, because the approval digest is computed from the caller's params and that is what makes a retry match.

Three verdicts: returns normally, raises `Denied`, or raises `PendingApproval`. Four gates, in order:

1. **Permission** — an explicit grant covers `(action, scope)`, or the principal holds it implicitly
2. **Configuration** — `action.configured_for?(scope)` (tool actions only)
3. **Approval policy** — matched contextually, may park the call
4. **Ledger, then execute** — write-ahead row, finalized once

Block form wraps execution. Handle form returns an `Authorization` the caller finalizes later (the API layer does this from an `around_action`).

## Actions

| Kind | Scope | Origin |
|---|---|---|
| `system` | global rows (`workspace_id` nil) | seeded from `Ability::Action::RESOURCES × ACTIONS` |
| `tool` | workspace-scoped | minted by enabling a capability on a connection |

- Key format is `<integration_slug>.<tool_name>`, **per instance**. Two Datadog connections mint `datadog.logs_query` and `datadog_eu.logs_query`, so a grant is never ambiguous and the ledger always says which one ran.
- **The slug is immutable after creation.** Renaming would orphan every grant, approval policy, and ledger row referencing the old key.
- `risk_level` (read/write/destructive) drives approval matching and the ledger. `reversible` marks what a human should always confirm.

## Who holds what without a grant

| Principal | Implicit authority |
|---|---|
| Admin or owner membership | every catalogued action, tool actions included |
| Member membership | system reads outside `ADMIN_ONLY_RESOURCES`, plus `incidents.create`, `incidents.update`, `chats.update` and `chats.delete` |
| Personal token / OAuth connection | exactly what that human holds |
| Service key | nothing, explicit grants only |
| `Agent` | nothing, explicit grants only |

An `Agent` row is created under **Gateway → Agents**, which mints its first token in the same step, since an agent without a credential can do nothing and making that a second step is a step everyone forgets. It arrives with zero grants: it can authenticate and nothing else until someone grants it something on the Permissions screen, where it appears alongside members and service keys (`Ability::Principal.all`). Its tokens are managed on the Agents screen rather than on **Developer → API Keys**, which filters agent keys out (`agent_id: nil`) so an agent's lifecycle lives in one place. Disabling an agent leaves the row listed with a way back on, because a vanished row still holds its slug and its grants.

Enabling a capability **is** the admin's deliberate decision, so it takes effect without a second grant step. The rule that must not bend: **machines never inherit a human's reach.** A service key or agent reaches an external system only through a grant someone created for it.

**Incident participation is member-level authority**, because responding to an incident is what a member is for, and it has to read the same on every surface — a responder closing an incident from Slack, from the API with a personal token, and through MCP is one person doing one thing. `WorkspaceMembership::PARTICIPATION` is the whole list. It also holds `chats.update` and `chats.delete`, since a person's chats with the agent are theirs to rename, pin, archive and delete. Asking the agent in a chat is `investigations.create`, not a chat permission, because it spends money. Configuring the workspace stays admin territory. This is deliberately *implicit* rather than a grant every workspace would have to hand out: making it revocable would mean deny-grants, and a permission system with a deny list stops being readable.

`Ability::Action::ADMIN_ONLY_RESOURCES` (integrations, api_keys, permissions, workspace) are the controls that decide access itself. Their actions exist as system rows so the gateway and the ledger treat them like everything else, but `Ability::Grant`, `Ability::RoleAction` and the API key matrix refuse them, `grantable_actions` hides them, and a member is refused even the read. Only admin access reaches them, on every surface.

Principals are workspace members, customer created `Agent`s, service `ApiKey`s, and `SystemAgent`s. The last are Firefight's own agents, global rather than owned by a workspace, so `Ability::Resolver.resolve` takes the workspace as a required argument and grants are filed per workspace. A default that read the principal's own workspace would be right for every other kind and silently wrong for these.

`Principal#implicit_authority` names what a principal holds before any grant, and `implicitly_allowed?` enforces it. **They are two halves of one rule, so change them together** — the permissions page explains the first and the gateway obeys the second, and a drift between them is a lie told to whoever is handing out access.

## Granting

Gateway → Permissions (`AbilityGrantsController`) is the only UI that writes grants. A grant carries an `Ability::Scope`: a hash of dimension to allowed catalog-entry ids, where a **missing dimension means unrestricted and an empty array is invalid**, never a way to say "all". The controller drops ids that are not the workspace's own environments rather than trusting the form, and a second grant of the same action retargets the existing row instead of duplicating it (one grant per principal per action **per workspace** is a DB invariant, because a principal can be global).

**Permission sets** (`Ability::Role`) bundle actions so a set is granted once instead of fifteen actions individually. Keep the set about *what* and the grant about *where*: one "Database read-only" set granted twice, scoped to Development for a contractor and unscoped for staff, beats two sets that drift the moment a provider adds a tool. `Ability::RoleAction#default_scope` pins a scope to one action inside a set and applies only when the grant carries none, so treat it as an override rather than the main mechanism. Editing a set changes what every holder can do immediately, and deleting one revokes it everywhere.

**Do not tie permission sets to `IncidentRole`.** Incident staffing is assigned mid-incident, often by the person taking the role, so letting it confer reach turns self-assignment into unapproved escalation. Temporary reach belongs to time-bound grants instead.

Environment scoping is the axis to reach for when the same connection serves dev and prod: one connection, one `IntegrationEnvironment` per environment, and grants scoped to each. Separate connections are for separate accounts, where the action keys should differ.

## Config ≠ permission

Both are required and they answer different questions. A grant says *this principal may*; a wired `IntegrationEnvironment` says *this connection can*. The gateway asks `action.configured_for?(scope)` and the action delegates to whatever minted it. **Never reach into `Integration::Tool` from the gateway** — new executor kinds must not add branches to the governance layer.

## Adding a provider

1. An entry in `config/integration_providers.yml`: `key`, `name`, `category`, `mark`, `color`, `description`, and `server_url` when the provider hosts an MCP server.
2. A logo at `public/integrations/<key>.svg`, white-filled on a 24x24 viewBox (Simple Icons is the source for the existing set). `ProviderMark` falls back to the `mark` letters if it is missing, so this never breaks the page, but a test asserts every provider has one.
3. If the category is new, a line under `categories:` in the same file. Taglines are registry data precisely so this stays a config edit.
4. If its OAuth needs a pre-registered app: `INTEGRATION_<KEY>_CLIENT_ID` and `_CLIENT_SECRET`. Add `_APP_SLUG` when the provider gates access behind installing the app (GitHub). Providers whose authorization server offers dynamic registration (Linear) need none of these.

Before adding one, confirm the endpoint rather than guessing it: `/.well-known/oauth-protected-resource<path>` should return the resource metadata and name an authorization server. If `scopes_supported` is absent there, read the note under OAuth below before assuming scopes can be requested.

**That is the whole job. No code.** A provider later gaining a first-party pack changes how it executes, never how it is listed.

## Native packs

A provider marked `kind: native` in the registry executes through a first-party Ruby pack instead of an MCP server. Everything downstream of execution is identical — same `Integration::Tool` allowlist, same minted actions, same gateway, same ledger — and the connect flow simply skips the server URL.

- **`Integration#executor` is the one place kinds diverge.** It returns the per-kind facade (`McpExecutor` or `NativeExecutor`), and each facade owns the whole provider conversation: `call` (execute an authorized invocation), `tool_definitions` (what the provider offers, as `Integrations::ToolDefinition` rows), and `check_health!` (probe with a row's credentials). Discovery, health checks, and `ConnectionToolFactory` go through the facade and never branch on kind — adding a kind is one facade class, touching no existing flow.
- A pack subclasses `Integrations::NativePack`, declares its tools with the `tool` DSL (name, description, params schema, read-only flag), and implements one instance method per tool. The declarations are the native analogue of an MCP server's `tools/list`; `DiscoveryService` reconciles both with the same semantics (arrive disabled, vanished tools marked removed never deleted).
- `Integrations::NativePack::REGISTRY` maps provider key to pack class. A registry sanity test fails if a `kind: native` provider has no pack.
- **Declaring a new tool on a shipped pack does not reach existing connections.** Discovery runs at connect and at **Refresh tools**, and the health sweep only probes. So adding a tool means either every admin clicks Refresh or the PR carries a data migration calling `DiscoveryService.sync!` for `kind: native` integrations (`20260912140000_sync_native_integration_tools`). Native definitions come from code, so that migration calls no provider.
- **Errors share one hierarchy.** `Integrations::Error` is the base; `McpClient::Error` and `NativePack::Error` subclass it, and rescue sites catch the base so they never grow with new kinds. A pack's `check_health!` raises `NativePack::Error` with a readable reason and the row records as failing.
- **Results share one shape.** Executors normalize through `Integrations::ToolResult` on the way out (MCP content shape), so callers read `result["content"]` without defending.
- Adding a native provider = the registry entry with `kind: native`, the pack class, and its `REGISTRY` line. The `http` kind remains a constant with no executor.
- **GitHub is the first native pack** (`Integrations::Packs::Github`): `pr_lookup`, `commit_lookup`, `recent_deployments`, `merged_pull_requests`, `running_commit`, `compare_commits` and `fetch_file` over the REST API, `blame` over GraphQL (the REST API has no blame), and `code_search` still against a warm local clone. `fetch_file` and `blame` take a `ref`, so the agent reads the code as it was at the running commit, and every file result carries a link pinned to that commit. `running_commit` returns the last deployment whose own last status is success before a given time, preferring an environment that looks like production, and the one before it to compare against. With no deployment record it falls back to the default branch at that time plus what reached it in the day before, and says in its answer that a merge is not proof of a deploy. `compare_commits` returns the commits, their pull requests with authors and reviewers, the changed files grouped by `CodeChange.kind_for` (migrations, config, feature flags, dependencies, infrastructure, code, tests, docs, in that order), dependency bumps read by `CodeChange::DependencyBumps`, owners from `CODEOWNERS` read by `CodeChange::Owners`, and every diff in the same order. `CodeChange` knows no code host, so a GitLab pack reuses it. `changes_before` (`Github::ChangesBefore`) answers what changed before a time across every repository the installation can see: one commit search per owner for the window, the repositories the clues point at (names, stack frames located through each candidate's tree with a suffix match so a container prefix such as `/app/` still matches, error text through code search), deploys read with the one just before the week so the first has something to compare against, rollbacks named when a deploy is behind the one before, a merge folded into the deploy that shipped it, the ranking from `CodeChange::Ranking`, blame on the failing lines, and a week's summary from each repository's last push. Every search is bounded and every bound it hits, and every search GitHub refuses, is named under Not checked. A deployment counts as succeeded when any of its statuses is success (`GithubApp.deployment_succeeded_at`), since GitHub marks an older deployment inactive once a newer one goes out, and it is timed when that status was written. `list_repositories` lists what the installation can see. `recent_deployments` reads GitHub deployment records, which exist only if the pipeline writes them, and takes the deployment target as `deployment_environment` because `ConnectionToolFactory` already owns the argument name `environment`. `merged_pull_requests` is the fallback when a repo has no deployment records, and it filters closed pull requests down to merged ones client-side because the REST API has no merged-only list. Connect is install-first without OAuth discovery — the customer installs the Firefight GitHub App, the callback brings back an `installation_id` (no tokens), and `Integrations::GithubApp` mints short-lived server-to-server installation tokens from it at call time, cached on the environment row. Requires `INTEGRATION_GITHUB_CLIENT_ID`, `_APP_SLUG`, and `_PRIVATE_KEY` (the App's PEM; the client id doubles as the JWT issuer).

## Clone manager

`Integrations::CloneManager` keeps warm local clones for the code tools. Repo content is untrusted input, so the rules are structural, not advisory:

- git runs with hooks disabled, prompts off, and no system config; arguments are exec'd as arrays, never through a shell.
- Tools read content only through git object commands (`git show`/`grep`/`blame`) — repo bytes never cross the filesystem API directly, and `..`/absolute paths are rejected at the argument boundary on top of git's own containment.
- Secrets-shaped paths (`.env`, credentials, key files) are refused in the executor and filtered from search results — the denylist lives in code, not in a prompt.
- The installation token rides a per-invocation `http.extraHeader` and is never written into the clone's config; git stderr is sanitized before it can reach an error message.
- Clones live under `REPO_CLONE_ROOT` (default `tmp/repo_clones`), namespaced per workspace, refreshed when older than 5 minutes at use, LRU-evicted over `REPO_CLONE_LIMIT` (default 20). An exclusive per-repo lock covers clone, fetch, eviction, and the read, so nothing rips a directory out from under a caller.
- In production the workers running these tools are the isolation boundary (dedicated service, restricted egress, volume encryption) — that part is infrastructure, documented in the deploy notes, not enforced by this class.

`Integrations::HealthCheckSweepJob` (recurring, every 30 minutes) probes every enabled environment row of every active integration with the executor's `check_health!` and records the result, so dead credentials surface before an incident needs the connection. Transitions to failing are logged; the admin-facing alert is a pending product decision.

## Connections

```
Integration (kind: mcp | http | native, immutable slug, kill switch)
├─ IntegrationEnvironment   per-environment encrypted credentials, health
└─ Integration::Tool        the allowlist; enabling mints one Ability::Action
```

- **Discovery never auto-enables anything.** Tools arrive disabled and an admin allowlists them.
- **Vanished tools are marked removed, never deleted or switched off.** `enabled` is the admin's allowlist and `removed_at` is whether the provider still offers the tool. Discovery writes only `removed_at`, so a tool that comes back keeps the admin's earlier choice. A removed tool cannot be toggled (the row's `toggle_blocked_reason` says why), is skipped by bulk enable, is not published over MCP, and fails the config check. Its action row and grants survive.
- Disabling an integration is a kill switch: its tools leave the outward MCP registry entirely.
- Every connect and refresh path goes through `Integrations::ConnectionRefresh`, so an unreachable server always lands as a readable error on the row instead of an exception a caller has to remember to catch.

## Connecting from a chat

The agent never connects anything. `list_integrations` says what a category holds, and the dashboard chat draws it as a card (`pages/agent/components/integration-card.tsx`) whose Connect button opens the same `ConnectDialog` the Integrations page uses, moved to `components/integrations/` so both pages share it. Where a provider stands (connected, needs attention, turned off, not connected), its label, and what a row offers (connect, reconnect or manage) are decided once, on `IntegrationProvider::Row`, from the workspace's rows and their health. The page and the Slack list both read them and decide nothing. A category's key is `IntegrationProvider.category_slug`, the same key the agent's tool groups use.

- **Back to the chat.** The dialog passes `return_to`, which `create`, `oauth_start` and the callbacks carry through the session and honour only when it is a chat on this dashboard (`safe_return_to`), so a crafted link cannot send someone elsewhere. The chat gets a toast saying the connection is made. From the Integrations page nothing changes.
- **A link that opens the dialog.** `/integrations?connect=<provider key>` (`Integration::CONNECT_QUERY_PARAM`) opens that provider's dialog on arrival, for whoever may manage integrations. The page reads both links from its address, the way the runbook sheet does. The Slack card's buttons use it, since OAuth cannot happen in Slack.
- **A connection's details have an address.** `/integrations?integration=<id>` (`Integration::DETAILS_QUERY_PARAM`) opens that connection's details sheet, and opening or closing the sheet rewrites the address, so it can be shared. The card's Manage link uses it, and names each connection when a provider backs several.
- **The rows are read fresh.** The chat page loads every category's rows on each visit (`integrationCards`), so coming back from connecting shows it connected without the agent being asked again.

## Credentials

- `Integrations::OauthClient` owns the credential shape: `exchange` produces it, `refresh` consumes and reproduces it, `stale?` reads its expiry. **Nothing else indexes into it.**
- `IntegrationEnvironment` owns persistence (`oauth`, `store_oauth!`, `rotate_oauth!`).
- `Integrations::Credentials` builds outbound headers and rotates expiring tokens before use.
- **Secrets never enter the session, an MCP tool response, or the ledger.** Alert-source tokens and OAuth client secrets are read server-side at the moment they are needed; connection UIs link to the settings page rather than returning a secret.

## OAuth

- **Nothing is persisted until the customer returns authorized.** Abandoning the provider's screen must leave no half-connected row.
- State is verified with a constant-time compare and every MCP flow runs PKCE. A pre-registered app (`_CLIENT_ID` / `_CLIENT_SECRET`) adds the client secret to the exchange but does not replace PKCE.
- Install-first connect (the provider's app install screen, `_APP_SLUG`) belongs to native packs only; see the Native packs section. The MCP client never builds an install URL.
- Discovery follows RFC 9728 then RFC 8414, trying the path-inserted, issuer-suffix, and OIDC metadata locations. Dynamic client registration is used when the server offers it.
- Requested scopes come from the resource metadata's `scopes_supported`. **Do not add a per-provider scope list to work around a provider that omits it.** Providers fronting their own hosted MCP server (PlanetScale) hold a fixed app scope set and ignore the `scope` parameter outright; the customer narrows access by picking organizations and databases on the consent screen, and an unticked organization is what a `forbidden` on an org-scoped call usually means. A scope list we cannot enforce reads as a least-privilege guarantee we do not have.

## Ledger

`Ability::Invocation` is written **before** execution and finalized exactly once.

- Denials: always recorded
- Allowed writes and destructive calls: always
- Allowed **tool** calls, reads included: always. Crossing into another system is the question an audit asks
- Allowed system reads: never, they run at request volume and the request log covers them
- `completed_at` nil means attempted with unknown outcome, the crash signal
- Identity is stored as values (labels), never join-dependent, so rows outlive their principals
- **No result bodies.** Outcome, error summary, and duration only

## Approvals

- `Policy::DOMAIN_APPROVALS` on the existing rule engine, matched over `{action_key, risk_level, reversible, environment, severity}`. Nothing sets `severity` in the context yet, so a rule on it never matches.
- One workspace-wide policy (`Workspace#approval_policy`), created by the first rule (`find_or_create_approval_policy!`). No policy means nothing waits, which is the default.
- Rules are written from Gateway → Permissions (`ApprovalRulesController`). The dialog asks three questions (abilities, risk levels, environments) and `PolicyRule::ApprovalConditions` turns them into `is_one_of` conditions, so the engine stays generic. Environment values are catalog-entry ids, matching grant scopes.
- Outcome contract (`PolicyRule::ApprovalOutcome`): `require: { role, count: 1, self_approval, notify, approvers, agents_may_approve }`. `approvers` is a list of `{ kind, id }` principal references (`Ability::Principal.reference`, a bare string is a person) validated against the policy's workspace. When present it replaces the role for deciding (`Ability::Approval#approver?`), and the role only describes the request. A role is only ever held by a person. A machine (agent or service key) can be named, and decides only when `agents_may_approve` is true, which the validator enforces at write time and `approver?` again at click time. `approver` on the approval is polymorphic for the same reason.
- `notify` is `channel` (incidents channel, the default), `dm` (each approver, named or everyone holding the role), or `both`. `ApprovalNotificationService.post!` fans out and records every posted message on `approval.notifications`, and `mark_resolved!` rewrites each one.
- Bound to a digest of action, params, and scope, so an approval admits exactly one call and is single-use
- Resuming re-enters `authorize!`: grants and config are re-checked against current state, only the policy match is skipped
- `approvals.*` and `permissions.*` are exempt from policy matching (`Ability::Action.approval_exempt?`): resolving an approval would otherwise need an approval, and a rule that held the Permissions screen could lock admins out of removing it
- Self-approval is allowed by default (a human confirming their own agent's proposal is the safety mechanism). Opt into four-eyes per rule with `require.self_approval: false`

## MCP exposure

- Read and config-write tools declare `authorize_as <resource>, <action>`; upserts override `authorization(workspace, args)` with a **side-effect-free** probe so create and update authorize differently
- Connection tools are published outward by `Mcp::ConnectionToolFactory`, so the same registry serves inbound and outbound
- `approval_id` rides **outside** the digested params, so an approved retry hashes identically to the original request
- Incident lifecycle writes stay out of MCP until they carry the full approval UX
