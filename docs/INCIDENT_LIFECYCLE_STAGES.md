# Incident Lifecycle Stages — Implementation Plan

## Context

Firefight currently groups incident statuses into 2 categories (`live`, `closed`) via a string column on `incident_statuses`. Both incident.io and Rootly group statuses into lifecycle stages (Triage, Active, Closed, Canceled). We need to expand this to support triage workflows, incident cancellation, and clean metrics — while keeping defaults simple for SMB startups.

Decision: Create a separate `incident_lifecycle_stages` table (global, system-managed) that statuses belong to. Stages are defined by Firefight, not per-workspace. Statuses remain workspace-scoped and customizable.

---

## Schema Changes

### New table: `incident_lifecycle_stages`

Global reference table (no `workspace_id`). System-managed, seeded on deploy.

```ruby
create_table :incident_lifecycle_stages, id: :uuid do |t|
  t.string :key, null: false, index: { unique: true }  # "triage", "active", "closed", "canceled"
  t.string :name, null: false                           # "Triage", "Active", "Closed", "Canceled"
  t.text :description
  t.integer :position, null: false                      # UI ordering
  t.timestamps
end
```

Seeded rows:

| key | name | position | description |
|---|---|---|---|
| triage | Triage | 1 | Potential incident, not yet confirmed |
| active | Active | 2 | Confirmed incident, being worked on |
| closed | Closed | 3 | Resolved |
| canceled | Canceled | 4 | False positive or duplicate |

### Modify table: `incident_statuses`

- Add `incident_lifecycle_stage_id` (FK to `incident_lifecycle_stages`, not null)
- Migrate existing data: `category = "live"` → active stage, `category = "closed"` → closed stage
- Remove `category` column after migration

### Default seeded statuses (per workspace)

| Stage | Status | Slug | Position | is_default |
|---|---|---|---|---|
| Triage | Triage | triage | 1 | false |
| Active | Investigating | investigating | 2 | **true** |
| Active | Identified | identified | 3 | false |
| Active | Monitoring | monitoring | 4 | false |
| Closed | Resolved | resolved | 5 | false |
| Canceled | Canceled | canceled | 6 | false |

Manual incident creation → Investigating (active). Workspaces can change `is_default` to Triage if they prefer triage-first flow.

---

## Status Transitions

### Free-form transitions (no hard constraints)

Any status can transition to any other status regardless of stage. The system behavior is driven by the **destination stage**, not the source:

- Moving **to active** → clear `resolved_at` (if set)
- Moving **to closed** → set `resolved_at`, clear `next_update_at`
- Moving **to canceled** → do NOT set `resolved_at`, clear `next_update_at`
- Moving **to triage** → clear `resolved_at` (if set)

This means:
- Active → Triage: allowed ("we declared but we're actually not sure")
- Triage → Active: allowed ("confirmed, this is real")
- Active → Canceled: allowed ("false alarm")
- Closed → Active: allowed (reopen)

### Default stage per entry point

| Entry point | Default stage | Reason |
|---|---|---|
| Slack manual (`/firefight`, shortcut) | Active (Investigating) | Human declared = already triaged mentally |
| API (future) | Triage | Automated = needs human confirmation |
| Alert auto-creation (future) | Triage | Machine signal = needs human confirmation |

All entry points can override the default by passing a specific status. API can create directly in Active if the caller knows the incident is confirmed.

### Future: Sequential mode (opt-in)

Rootly calls this "Lifecycle Preferences" — either flexible (any status → any status) or sequential (must follow stage order). We start with flexible. Sequential can be added later as a workspace setting.

---

## Model Changes

### New model: `IncidentLifecycleStage`

```
app/models/incident_lifecycle_stage.rb
```

- Constants: `KEY_TRIAGE`, `KEY_ACTIVE`, `KEY_CLOSED`, `KEY_CANCELED`
- Class methods: `.triage`, `.active`, `.closed`, `.canceled` (find by key)
- Instance methods: `.triage?`, `.active?`, `.closed?`, `.canceled?`
- `has_many :incident_statuses`

### Modified model: `IncidentStatus`

```
app/models/incident_status.rb
```

- Replace `CATEGORY_LIVE`, `CATEGORY_CLOSED`, `CATEGORIES` constants → delegate to stage
- `belongs_to :incident_lifecycle_stage`
- Replace scopes: `.live` → `.active` (via stage), `.closed` (via stage), add `.triage`, `.canceled`
- Replace instance methods: `.live?` → `.active?`, keep `.closed?`, add `.triage?`, `.canceled?`
- Convenience: `delegate :key, to: :incident_lifecycle_stage, prefix: :stage` — so `status.stage_key == "active"`

### Modified model: `Incident`

```
app/models/incident.rb
```

- Scopes: `.active` stays (now via stage), `.closed` stays, add `.triage`, `.canceled`
- Add `.not_canceled` scope for metrics queries
- Instance methods: `.active?` stays, `.closed?` stays, add `.triage?`, `.canceled?`

### Modified concern: `Incident::Lifecycle`

```
app/models/concerns/incident/lifecycle.rb
```

Current behavior preserved + new stage behavior:

- **triage → active**: no timestamp changes (future: could set `confirmed_at`)
- **any → closed**: set `resolved_at`, clear `next_update_at` (current behavior)
- **any → canceled**: do NOT set `resolved_at`, clear `next_update_at`
- **closed/canceled → active**: clear `resolved_at` (current reopen behavior)

### Modified concern: `Workspace::IncidentDefaults`

```
app/models/concerns/workspace/incident_defaults.rb
```

- Seed 6 statuses (up from 4) across all 4 stages
- Look up stages by key: `IncidentLifecycleStage.find_by!(key: "active")`

---

## Code Touchpoints

All references to `CATEGORY_LIVE`, `CATEGORY_CLOSED`, `.live?`, `.live` scope need updating:

**Handlers** (use `incidents.active` scope — no change needed, already named correctly):
- `commands/firefight/close_handler.rb` — `.active` scope, no change
- `commands/firefight/reopen_handler.rb` — `.closed` scope, no change
- `commands/firefight/actions_handler.rb` — `.active` scope, no change
- `commands/firefight/followups_handler.rb` — `.active` scope, no change
- `commands/firefight/summary_handler.rb` — `.active` scope, no change
- `commands/firefight/lead_handler.rb` — `.active` scope, no change
- `commands/firefight/severity_handler.rb` — `.active` scope, no change
- `commands/firefight/status_handler.rb` — `.active` scope, no change
- `commands/firefight/update_handler.rb` — `.active` scope, no change
- `events/reaction_added_handler.rb` — `.active` scope, no change

**Handlers needing updates:**
- `interactions/close_incident_handler.rb` — `workspace.incident_statuses.closed.first` → use stage-based scope
- `interactions/reopen_incident_handler.rb` — `workspace.incident_statuses.live.find_by(is_default: true)` → `.active` scope

**Other:**
- `incident_update_reminder_job.rb` — `incident.active?` — no change (method renamed internally)
- `slack/modal_builder.rb` — `workspace.incident_statuses.active.ordered` — `.active` here means non-deleted (soft delete scope), need to disambiguate from stage scope
- `incident_status.rb` — replace category constants/validations with stage FK
- `incident.rb` — update scope definitions to join through stage
- `incident/lifecycle.rb` — add canceled stage handling
- `workspace/incident_defaults.rb` — seed new statuses

**Tests:**
- `incident_status_test.rb` — update scope/method tests
- `close_incident_handler_test.rb` — verify behavior unchanged
- `reopen_incident_handler_test.rb` — verify behavior unchanged
- Add tests for new triage and canceled behaviors

---

## Scope Naming Disambiguation

Current ambiguity: `IncidentStatus.active` means "not soft-deleted" (`where(deleted_at: nil)`), but we also want `.active` to mean "in the active lifecycle stage."

Resolution:
- Rename soft-delete scope from `.active` to `.kept` (or `.visible`, `.not_deleted`)
- `.active` now means "statuses in the active lifecycle stage"
- Apply same rename on any other model using `.active` for soft-delete

---

## Migration Strategy

Single migration with 3 phases:

1. Create `incident_lifecycle_stages` table and seed 4 rows
2. Add `incident_lifecycle_stage_id` column to `incident_statuses` (nullable initially)
3. Backfill: `category = "live"` → active stage ID, `category = "closed"` → closed stage ID
4. Make `incident_lifecycle_stage_id` not null
5. Remove `category` column

---

## Seed Changes

New statuses added to `Workspace::IncidentDefaults`:
- "Triage" (triage stage, position 1)
- "Canceled" (canceled stage, position 6)

Existing statuses updated:
- Link to lifecycle stage instead of category string
- Positions shifted to accommodate Triage at position 1

For existing workspaces: a data migration creates the 2 new default statuses.

---

## Verification

1. `bin/ci` — all existing tests pass (after updates)
2. New model tests for `IncidentLifecycleStage`
3. Updated `IncidentStatus` tests for stage-based scopes
4. Verify `Incident::Lifecycle` concern:
   - active → closed: `resolved_at` set
   - active → canceled: `resolved_at` NOT set
   - closed → active: `resolved_at` cleared
   - canceled → active: works correctly
   - triage → active: no side effects
   - triage → canceled: `resolved_at` NOT set
5. Verify default seeding: `Workspace.create!` seeds 6 statuses across 4 stages
6. Manual test: create incident via Slack, verify it starts in Investigating (active stage)
