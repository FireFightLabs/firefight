# Integrations & the Ability Gateway

One system seen from two ends. **Connections mint abilities; the gateway authorizes every use of one.** Enabling a capability on a connection card creates exactly one permissioned action, and from that moment it is grantable, approvable, and ledgered like anything else in the product.

## The chokepoint

Every privileged operation goes through one method:

```ruby
AbilityGateway.authorize!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {}) { execute }
```

API controllers, MCP dispatch, and connection tools all route here. **Never check permissions inline** anywhere else; the convergence is the safety property.

Three verdicts: returns normally, raises `Denied`, or raises `PendingApproval`. Four gates, in order:

1. **Permission** — an explicit grant covers `(action, scope)`, or the principal holds it implicitly
2. **Configuration** — `action.configured_for?(scope)` (tool actions only)
3. **Approval policy** — matched contextually, may park the call
4. **Ledger, then execute** — write-ahead row, finalized once

Block form wraps execution. Handle form returns an `Authorization` the caller finalizes later (the API layer does this from an `around_action`).

## Actions

| Kind | Scope | Origin |
|---|---|---|
| `system` | global rows (`workspace_id` nil) | seeded from `ApiKey::RESOURCES × ACTIONS` |
| `tool` | workspace-scoped | minted by enabling a capability on a connection |

- Key format is `<integration_slug>.<tool_name>`, **per instance**. Two Datadog connections mint `datadog.logs_query` and `datadog_eu.logs_query`, so a grant is never ambiguous and the ledger always says which one ran.
- **The slug is immutable after creation.** Renaming would orphan every grant, approval policy, and ledger row referencing the old key.
- `risk_level` (read/write/destructive) drives approval matching and the ledger. `reversible` marks what a human should always confirm.

## Who holds what without a grant

| Principal | Implicit authority |
|---|---|
| Admin or owner membership | every catalogued action, tool actions included |
| Member membership | system reads only |
| Personal token / OAuth connection | exactly what that human holds |
| Service key | nothing, explicit grants only |
| `Agent` | nothing, explicit grants only |

Enabling a capability **is** the admin's deliberate decision, so it takes effect without a second grant step. The rule that must not bend: **machines never inherit a human's reach.** A service key or agent reaches an external system only through a grant someone created for it.

`Principal#implicit_authority` names what a principal holds before any grant, and `implicitly_allowed?` enforces it. **They are two halves of one rule, so change them together** — the permissions page explains the first and the gateway obeys the second, and a drift between them is a lie told to whoever is handing out access.

## Granting

Settings → Permissions (`AbilityGrantsController`) is the only UI that writes grants. A grant carries an `Ability::Scope`: a hash of dimension to allowed catalog-entry ids, where a **missing dimension means unrestricted and an empty array is invalid**, never a way to say "all". The controller drops ids that are not the workspace's own environments rather than trusting the form, and a second grant of the same action retargets the existing row instead of duplicating it (one grant per principal per action is a DB invariant).

**Permission sets** (`Ability::Role`) bundle actions so a set is granted once instead of fifteen actions individually. Keep the set about *what* and the grant about *where*: one "Database read-only" set granted twice, scoped to Development for a contractor and unscoped for staff, beats two sets that drift the moment a provider adds a tool. `Ability::RoleAction#default_scope` pins a scope to one action inside a set and applies only when the grant carries none, so treat it as an override rather than the main mechanism. Editing a set changes what every holder can do immediately, and deleting one revokes it everywhere.

**Do not tie permission sets to `IncidentRole`.** Incident staffing is assigned mid-incident, often by the person taking the role, so letting it confer reach turns self-assignment into unapproved escalation. Temporary reach belongs to time-bound grants instead.

Environment scoping is the axis to reach for when the same connection serves dev and prod: one connection, one `IntegrationEnvironment` per environment, and grants scoped to each. Separate connections are for separate accounts, where the action keys should differ.

## Config ≠ permission

Both are required and they answer different questions. A grant says *this principal may*; a wired `IntegrationEnvironment` says *this connection can*. The gateway asks `action.configured_for?(scope)` and the action delegates to whatever minted it. **Never reach into `Integration::Tool` from the gateway** — new executor kinds must not add branches to the governance layer.

## Adding a provider

1. An entry in `config/integration_providers.yml`: `key`, `name`, `category`, `mark`, `color`, `description`, and `server_url` when the provider hosts an MCP server.
2. If its OAuth needs a pre-registered app: `INTEGRATION_<KEY>_CLIENT_ID` and `_CLIENT_SECRET`. Add `_APP_SLUG` when the provider gates access behind installing the app (GitHub).

**That is the whole job. No code.** A provider later gaining a first-party pack changes how it executes, never how it is listed.

## Connections

```
Integration (kind: mcp | http | native, immutable slug, kill switch)
├─ IntegrationEnvironment   per-environment encrypted credentials, health
└─ Integration::Tool        the allowlist; enabling mints one Ability::Action
```

- **Discovery never auto-enables anything.** Tools arrive disabled and an admin allowlists them.
- **Vanished tools are disabled, never deleted.** Their action rows and grants survive, and the config check stops the calls.
- Disabling an integration is a kill switch: its tools leave the outward MCP registry entirely.
- Every connect and refresh path goes through `Integrations::ConnectionRefresh`, so an unreachable server always lands as a readable error on the row instead of an exception a caller has to remember to catch.

## Credentials

- `Integrations::OauthClient` owns the credential shape: `exchange` produces it, `refresh` consumes and reproduces it, `stale?` reads its expiry. **Nothing else indexes into it.**
- `IntegrationEnvironment` owns persistence (`oauth`, `store_oauth!`, `rotate_oauth!`).
- `Integrations::Credentials` builds outbound headers and rotates expiring tokens before use.
- **Secrets never enter the session, an MCP tool response, or the ledger.** Alert-source tokens and OAuth client secrets are read server-side at the moment they are needed; connection UIs link to the settings page rather than returning a secret.

## OAuth

- **Nothing is persisted until the customer returns authorized.** Abandoning the provider's screen must leave no half-connected row.
- State is verified with a constant-time compare; PKCE is used except on the install-first path, where a registered app's client secret authenticates the exchange instead.
- **Install-first** (`_APP_SLUG` set) starts at the provider's install screen so customers pick their account and repositories from our UI and never visit the provider's site to install by hand.
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

- `Policy::DOMAIN_APPROVALS` on the existing rule engine, matched over `{action_key, risk_level, reversible, environment, severity}`
- Bound to a digest of action, params, and scope, so an approval admits exactly one call and is single-use
- Resuming re-enters `authorize!`: grants and config are re-checked against current state, only the policy match is skipped
- `approvals.*` actions are exempt from policy matching, otherwise resolving an approval would need an approval
- Self-approval is allowed by default (a human confirming their own agent's proposal is the safety mechanism). Opt into four-eyes per policy with `require.self_approval: false`

## MCP exposure

- Read and config-write tools declare `authorize_as <resource>, <action>`; upserts override `authorization(workspace, args)` with a **side-effect-free** probe so create and update authorize differently
- Connection tools are published outward by `Mcp::ConnectionToolFactory`, so the same registry serves inbound and outbound
- `approval_id` rides **outside** the digested params, so an approved retry hashes identically to the original request
- Incident lifecycle writes stay out of MCP until they carry the full approval UX
