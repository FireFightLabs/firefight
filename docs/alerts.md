# Alerts

Machine-generated entry into incidents. A monitoring tool POSTs JSON, a routing policy decides what happens, and an incident is opened, joined, announced, or dropped. **Assume every source is noisy, retries aggressively, and fires in storms** — most of the non-obvious code in this subsystem is a de-duplication or concurrency guard, not business logic.

Two halves that must not be conflated:

- **Ingestion** (`Alert`, `AlertSource`, `AlertGroup`, `AlertIngestService`) is alert-specific.
- **PolicyRouter** (`Policy`, `PolicyRule`, `Policy::Evaluation`) is a generic rules primitive that alert routing is merely the first consumer of. Auto-investigate and the Ability Gateway's approval policies are meant to reuse it unchanged. Never add alert vocabulary to the engine.

## The pipeline

```
POST /api/v1/alerts/:endpoint_path
  → Api::V1::AlertsController          guards, per-source auth, rate limit
  → AlertProviders::<Provider>         verify + normalize into an ARRAY of items
  → AlertIngestService#ingest          resolve / dedup / flap / persist
  → AlertIngestService#route           CAS, policy evaluation, outcome
      → Policy#evaluate                 first-match-wins, pure, traced
      → Alert::TargetResolver           catalog lookups at fire time
      → IncidentLifecycleService#create incident, if the outcome asks for one
  → (after commit) WorkspaceAdapter     one throttled digest message
```

`Alerts::RoutingSweepJob` (in `config/recurring.yml`) closes the loop for anything left `pending`.

## Storm control is layered

The one thing to remember. Every layer exists because the one above it can be bypassed, and **removing any of them turns a flapping monitor into thousands of channels**:

| Layer | Mechanism | Where |
|---|---|---|
| Per-source rate limit | 429 (providers retry) counting **items**, not requests | `AlertsController#within_rate_limit?` |
| Redelivery idempotency | unique index on `(alert_source_id, external_id)` | `AlertIngestService#persist` rescue |
| Fingerprint dedup | partial unique index on open `(alert_source_id, fingerprint)` | `#ingest` open-alert branch |
| Flap debounce | re-fire inside `flap_window` reopens the same row | `#recently_resolved` / `#reopen` |
| Grouping | `AlertGroup` signature + window under an advisory lock | `#apply_outcome` |
| Digest throttle | one message per alert, updated, max one send a minute | `#notify_digest` |
| Never auto-close | a resolved alert never closes its incident | `#handle_resolved` |

A monitor that fires 10,000 times in five minutes produces one alert row, one incident, and one Slack message reading `fired 10000x`.

**Incidents are never auto-closed from a resolved alert.** A resolve marks the alert and updates the digest, nothing else. Closing is a human decision, and a resolved-then-refired alert is a fresh episode, not a reopened one.

## Entry point

`config/routes.rb`: `post "alerts/:endpoint_path", to: "alerts#create"`.

`Api::V1::AlertsController` inherits `ActionController::API` directly, **not `BaseController` and not `ApiController`**. Alert auth is a third scheme: the unguessable path identifies the source, and the secret is verified by that source's provider adapter. Slack signatures and Bearer API keys have nothing to do with it.

The action is a gauntlet of cheap rejections before any work happens: unknown or disabled path (404), suspended workspace (403), body over `MAX_PAYLOAD_BYTES` (413), failed verify (401), unparseable or unrecognized payload (422), batch over `MAX_BATCH_ITEMS` (422), rate limited (429).

- **Every rejection calls `source.record_rejection!(reason)`** and every accepted request calls `record_received!`. Those two columns are the entire diagnostic story on the sources screen when someone's webhook is silently misconfigured. A new rejection path that skips them is a support ticket nobody can answer.
- **The item loop rescues per item.** One malformed alert in a batch of fifty must not fail the other forty-nine; the response reports `{ ok:, received:, failed: }`.
- Ingest limits are caps on *work*, not on politeness. The rate limiter counts items so a single POST cannot smuggle unbounded work past a per-minute limit.

## Provider adapters

`app/adapters/alert_providers/` is the inbound mirror of the platform adapter layer: **the only place that knows what a given vendor's JSON looks like.** `AlertProviders.for(provider)` resolves the registry in `alert_providers.rb`; adding a provider is a class plus a registry entry plus an `AlertSource::PROVIDER_*` constant.

The contract (`AlertProviders::Base`) is two class methods:

```ruby
def self.verify(headers:, raw_body:, source:)  # -> boolean
def self.normalize(payload, source:)           # -> [ { fields:, payload: }, ... ]
```

- **`normalize` always returns an array.** Alertmanager and Grafana batch. Each item carries **its own payload slice**, so a batch of fifty stores fifty slices rather than fifty copies of the whole body.
- **`NORMALIZED_FIELDS` is the vocabulary everything downstream speaks**: `external_id fingerprint status title description service severity_raw team environment`. Nothing past the adapter may reference a vendor-specific key.
- Adapters are thin boundary normalizers: no persistence, no business logic, no Slack.
- Verification uses `ActiveSupport::SecurityUtils.secure_compare`, never `==`. Providers without native signatures (Datadog, Grafana) get shared-token comparison and nothing more; do not invent a signature scheme they do not send.
- An item where no mapped field resolved is noise, not an alert. `recognized?` returning false is what turns garbage into a diagnosable 422 instead of a row of nulls.

`Generic` is the workhorse and covers any tool that can POST with a header token. Extraction is **declarative dot-path lookup only** (numeric segments index arrays), overridable per source via `config["field_map"]`, with `config["items_path"]` splitting a batch. **No Liquid, no JS, no CEL** — that is a decision, not an omission. If a payload cannot be expressed as dot-paths, write an adapter.

## Ingestion

`AlertIngestService#ingest` branches in a fixed order, and the order is the semantics:

1. **Resolved** → `handle_resolved`: resolve the open alert, write `IncidentEvent::ALERT_RESOLVED`, force a digest update. No incident change.
2. **Already firing** → `record_firing!` and return. One indexed UPDATE. No new row, no new incident, no new channel.
3. **Recently resolved** → `reopen`: the same row fires again.
4. **New** → `persist`, then route inline.

`Alert#record_firing!` is a single atomic `update_all` (`event_count = event_count + 1`) precisely so concurrent firings cannot lose increments. **Never rewrite it as read-modify-write.**

The fingerprint is the answer to "is this the same alert as before?" — the provider's own if it sends one, otherwise `Alert.fallback_fingerprint` over the source's `fingerprint_fields` (default `service`, `title`).

### Persist-first, never check-then-insert

`#persist` inserts and rescues `RecordNotUnique`, distinguishing the two unique indexes by which lookup succeeds:

- `external_id` hit → byte-identical redelivery, already counted.
- otherwise → lost the open-fingerprint insert race; the winner's row is authoritative, so count this firing there.

**Only the request that won the insert routes inline.** Losers leave it to the winner or the sweep.

### Flapping onto a closed incident

`#reopen` has one subtle case worth preserving: if the attached incident is already `terminal?`, the alert **detaches from everything** (incident, group, matched rule, channel, message, notified-at) and returns to `routing_state: pending` for a fresh route. Otherwise the regression would edit a digest inside a closed, possibly archived channel and nobody would see it.

## Routing

`AlertIngestService#route` is the shape to copy, not to redesign:

```ruby
alert.with_lock do
  next unless alert.routing_state == Alert::ROUTING_PENDING   # CAS
  ...
end
deferred_notification&.call                                    # Slack after commit
```

- **Row-lock compare-and-swap on `routing_state`**, so a duplicate delivery, an overlapping sweep, and the inline path can all call `route` and exactly one applies.
- **Every Slack side effect is returned from `apply_outcome` as a lambda** and invoked after the transaction commits. A slow platform call must never hold a DB transaction open.
- **Failures never raise to the caller.** A failure *inside* the routing transaction calls `alert.record_routing_failure!`, which bumps `routing_attempts`, leaves the alert `pending`, and marks it `failed` at `MAX_ROUTING_ATTEMPTS`. A failure *after* the outcome commits is a notification problem, so it just logs and leaves the alert routed rather than sending it back to `pending` for the sweep to apply twice. The row is already safe, so a routing bug must not become a 500 that makes the provider retry ingestion.

### Which policy fires

`AlertSource#effective_alert_routing_policy`: **the source's own policy, then the workspace-wide policy as fallback, enabled only.** No match at all leaves the alert `unmatched`, which is a reportable state, not a failure. `Workspace#effective_alert_routing_policy` mirrors it so the tester and ingest can never disagree.

Policies carry a polymorphic `scoped_to` for exactly this reason. Alert routing scopes per `AlertSource`; a future domain scopes to an MCP server or environment. **Do not collapse it into one shared list with source conditions.**

The settings screen edits the scope's *own* policy, never the inherited fallback (`SettingsController#alert_routing`), while the tester resolves the *effective* one. Keep that distinction: it is the difference between "what am I editing" and "what would fire".

### The engine

`Policy::Evaluation` is a **model concern, not a service** — pure domain logic touching only its own rows. `policy.evaluate(context)` is first-match-wins over `ordered_rules`, returning `Result#matched_rule`, `#outcome`, and a full `#trace`. Because it is pure and traced, one implementation powers ingest routing, the route tester, and future read-only MCP evaluation.

- Conditions are **declarative field/operator/value only** (`is_one_of`, `contains`, `starts_with`, `matches_regex`, `is_empty`). No expression language, ever.
- Regexes carry `REGEX_TIMEOUT_SECONDS` against ReDoS and are compile-checked at write time in `PolicyRule#conditions_are_well_formed`. Both, not either.
- The engine never reads outcome vocabulary. `PolicyRule::AlertRoutingOutcome` is a **write-time validation contract for the consumer**, wired through `OUTCOME_VALIDATORS`. A new domain adds its own outcome module and nothing in the engine changes.

`Policy::ContextBuilder` enriches the flat alert fields from the catalog before evaluation: for each field naming a catalog system type it resolves the entry by slug, merges one relationship hop keyed by the related type's `system_key`, and merges scalar attributes as `<field>.<attribute>`. An alert saying only `service: auth_service` therefore evaluates against `team` and `service.tier` too. **Explicit input fields are never overwritten.**

### Outcomes

`drop`, `notify_only`, `attach_to_incident`, `auto_create_incident`. In `#apply_outcome`, the incident-bearing actions do:

1. `lock_signature!` — a transaction-scoped `pg_advisory_xact_lock` keyed on the content signature.
2. `grouped_incident` — an open `AlertGroup` in window whose incident is not terminal.
3. `create_incident` only when there is no group **and** the action is `auto_create_incident`.
4. `attach`, writing `IncidentEvent::ALERT_ATTACHED`.

**The advisory lock is what makes a storm produce one incident.** Two hundred same-signature alerts arriving simultaneously serialize through the lookup-then-create. `AlertGroup.signature_for` hashes the policy's `content_match_fields` (default `service`); the window defaults to `AlertGroup::DEFAULT_WINDOW_MINUTES` and is configurable from five minutes to seven days.

Incident creation goes through **`IncidentLifecycleService#create` with `source: Incident::SOURCE_ALERT` and `declared_by: nil`** — the same path `/ff declare` uses. Alerts are an entry point, not a second way to make an incident.

Severity resolves as `outcome["severity_id"]` → `AlertSource#resolve_severity` (per-source static `severity_map`) → workspace default. A workspace with no default severity raises, which is correct: silently inventing one is worse.

### Targets

`Alert::TargetResolver` turns outcome targets (`channel`, `member`, `team`, `owning_team`) into destinations. `owning_team` reads the alert's service field, finds the catalog entry, walks its relationships to a team, and takes the **service's own notification channel first, then the team's** (specific beats general).

- **People and channels resolve through attribute roles, never slugs.** Each catalog attribute definition can carry a `role` (`members`, `manager`, `notification_channel`, constants on `CatalogAttributeDefinition`), set in the type editor and seeded on the defaults. The resolver asks `entry.role_value(role)`, so a workspace can rename its attributes freely. `Alert::RoutingRoleGaps` names the roles the workspace's rules need but nothing is tagged for; the alert routing page shows them as a banner and MCP's `evaluate_routing` returns them as `role_warnings`.
- **Resolved at fire time, never stored**, so routing follows catalog reorgs automatically.
- **Every miss is a note, never an exception. The incident must always win.** Notes surface as `unresolved_targets` on the attach event and as warnings in the tester. A resolver that raises would let a catalog typo block an incident.

## Slack output

One digest message per alert, posted once and updated in place. `#notify_digest` claims the send with a **conditional UPDATE on `last_notified_at`**, the same CAS shape as routing, so concurrent firings race on an indexed write instead of queuing behind a row lock waiting on the platform API. Status transitions (attach, resolve) pass `force: true` to bypass `NOTIFY_MIN_INTERVAL`.

**The claim sticks even when the send fails**, deliberately: a storm into a broken channel must not retry on every delivery. `AdapterError` is logged and swallowed.

`Slack::Messages::Alert` is intentionally two blocks (title, then source / status / fire count / last seen). It is a digest that mutates, not a feed. See [slack-messages.md](slack-messages.md) for block conventions.

## Configuration surfaces

| Screen | Route | Owns |
|---|---|---|
| Alert sources | `/settings/alert-sources` | Sources, endpoint URL and token, severity map, field map, `items_path`, fingerprint fields, flap window |
| Alert routing | `/settings/alert-routing` | The policy: rules, conditions, outcomes, grouping window, content match fields, route tester |
| Alerts | `/settings/alerts` | Recent alerts filtered by source and matched rule. Operational, not configuration |

- **Secrets never enter page props.** `AlertSourcesController#token` serves the secret on demand behind the copy button, mirroring API keys. `#sample_payload` returns the latest raw payload so the field-mapping UI offers real keys to click instead of asking for dot-paths typed blind.
- **Only `AlertProviders::Base::NORMALIZED_FIELDS` are mappable**; the controller filters the submitted map rather than trusting it.
- Config knobs are **validated at write time** (`Policy::AlertRoutingConfig`, `AlertSource` clamping) so ingest never defends against nonsense values. `domain_config_merging` gives the form partial-update semantics: nil leaves a knob untouched, an empty list reverts to the default.
- Rule ordering is `priority`, unique per policy, reordered by `PolicyRulesController#move_up` / `#move_down`.

**The route tester is pure.** `AlertRoutingController#test` builds a context, evaluates, and returns `matched`, `outcome`, `context`, `trace`, and a dry-run resolution preview of who would be invited and notified. Actually delivering a message is a **separate explicit action** (`#send_test` → `AlertRoutingTestService`) which re-evaluates server-side, so the client never picks the destination. Dry run stays the default; never auto-send on test.

## Observability

`alerts.matched_policy_rule_id` is persisted at routing time (FK, nullify on rule delete) so **every routed alert can answer "which rule did this?"** permanently. That column is what makes the rule filter on the alerts screen and the MCP summary possible; do not drop it in favour of re-deriving.

Other surfaces: `AlertsPanel` on the incident page, `IncidentEvent::ALERT_ATTACHED` / `ALERT_RESOLVED` on the timeline, and `Mcp::Tools::SearchAlerts` (read-only, gated on `ApiKey::RESOURCE_ALERTS`) exposing status, routing state, matched rule priority, and incident identifier to agents.

## Adding a provider

1. Adapter class in `app/adapters/alert_providers/` implementing `verify` and `normalize`.
2. `AlertSource::PROVIDER_*` constant, added to `PROVIDERS`.
3. Registry entry in `AlertProviders::ADAPTERS`.
4. Adapter test under `test/adapters/alert_providers/` with a real captured payload.
5. Docs page in `../firefight-landing` telling users where to paste the endpoint and token.

**No auto-provisioning of the provider side.** Firefight never manages a customer's cloud API tokens; setup is manual copy-paste. Stored credentials belong to the integration layer ([integrations.md](integrations.md)), not here.

Prefer configuring `Generic` over writing an adapter when the payload is expressible as dot-paths — that is what `field_map` and `items_path` are for.
