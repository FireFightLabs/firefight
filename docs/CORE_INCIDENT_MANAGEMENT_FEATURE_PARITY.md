# Core Incident Management — Feature Parity Analysis

Gap analysis comparing Firefight's current state against incident.io and Rootly.
Scope: core incident management only (no postmortem, no integrations, no on-call/alerting).

---

## What Firefight Already Has (solid foundation)

- Workspace-scoped statuses (4), severities (3), roles (1) — all customizable
- Status categories: `live` / `closed`
- Incident lifecycle: create → update → close → reopen
- Role assignment framework (currently only Incident Lead)
- Action items with `action` / `followup` types and `open` / `in_progress` / `done` statuses
- Audit trail (incident_events) with before/after snapshots
- `custom_fields` JSONB column (unused)
- `declared_at`, `resolved_at` timestamps
- Update reminders via `next_update_at`
- Platform-agnostic normalizers, adapters, identifiers

---

## Gaps — Grouped by Priority

### 1. Status Lifecycle Stages (both competitors have this) → [INCIDENT_LIFECYCLE_STAGES.md](INCIDENT_LIFECYCLE_STAGES.md)

**Current**: 2 categories — `live`, `closed`
**Needed**: 3 stages — `triage`, `active`, `closed`

- **incident.io**: Triage → Active → Post-Incident. Triage incidents can be Accepted, Declined, or Merged before becoming "live"
- **Rootly**: Open → In Triage → Started → Mitigated → Resolved → Canceled

**Gap**: No triage stage. No concept of declining/canceling an incident. No way to group statuses into more granular lifecycle phases.

**What this enables**: Triage lets teams investigate potential incidents without polluting metrics. Canceled status handles false positives. Stages drive which UI/automations/forms appear at each phase.

---

### 2. Incident Types → [INCIDENT_TYPES.md](INCIDENT_TYPES.md)

**Current**: None
**Needed**: Workspace-configurable incident types

- **incident.io**: Types like "Production Outage", "Security Incident", "Data Breach". Types control which custom fields show, which roles are required, which severities are available, which workflows trigger
- **Rootly**: Similar — types as a custom property with name, slug, description, color. Drive automation conditions

**Gap**: No incident type concept. All incidents follow the same workflow regardless of nature.

**What this enables**: Different response playbooks per type. Field visibility conditional on type. Severity options scoped per type. Analytics sliced by type.

---

### 3. Timestamps / Milestones → [INCIDENT_TIMESTAMPS.md](INCIDENT_TIMESTAMPS.md)

**Current**: `declared_at`, `resolved_at` only
**Needed**: Multiple lifecycle timestamps, ideally configurable

- **incident.io**: Auto-creates a timestamp per status transition (e.g., "Fixed At" when entering Monitoring). Custom timestamps for milestones like "Impact Started At". Validation prevents illogical sequences
- **Rootly**: `detected_at`, `started_at`, `acknowledged_at`, `in_triage_at`, `mitigated_at`, `resolved_at` — all auto-set on status transitions, all retroactively editable

**Gap**: Only 2 timestamps. No `mitigated_at`, `acknowledged_at`, or per-status transition timestamps. No ability to record "when did impact actually start" vs "when did we declare".

**What this enables**: MTTR/MTTA/MTTD metrics. Duration between milestones. SLA tracking. Accurate incident timelines.

---

### 4. Services / Environments / Teams Affected → [SYSTEM_CATALOG.md](SYSTEM_CATALOG.md)

**Current**: None
**Needed**: Track which services, environments, and teams are impacted per incident

- **incident.io**: Custom fields for affected services/teams. Catalog integration auto-populates related data
- **Rootly**: First-class `services` and `environments` fields (multi-select). Service catalog with on-call integration. AI auto-tags incidents with service owner metadata

**Gap**: No way to record what service, environment, or team is affected. No service catalog.

**What this enables**: "Which service causes the most incidents?" analytics. Auto-routing to the right team. Environment-aware response (prod vs staging). Service ownership mapping.

---

### 5. Custom Fields (proper implementation) → [CUSTOM_FIELDS.md](CUSTOM_FIELDS.md) *(future)*

**Current**: JSONB column exists but no schema, no UI, no field definitions
**Needed**: Workspace-defined custom field types with validation

- **incident.io**: Text, Number, Single-select, Multi-select, Link. Conditional visibility per incident type. Required/optional per form phase (create, update, resolve)
- **Rootly**: Text, Textarea, Rich text, Tags, Number, Checkbox, Date, Datetime, Select, Multi-select. Conditional visibility/requirement based on other field values. Display or hide from UI

**Gap**: No custom field definitions table. No field type system. No validation. No conditional visibility.

**What this enables**: Organization-specific data capture (customer segment, region, product area, detection method). Analytics on any dimension. Workflow conditions on field values.

---

### 6. Incident Hierarchy / Relationships → [INCIDENT_RELATIONSHIPS.md](INCIDENT_RELATIONSHIPS.md)

**Current**: None
**Needed**: At minimum related incidents; ideally parent/child

- **incident.io**: Related incidents via similarity matching. Merging triage incidents into active ones. No formal parent-child
- **Rootly**: Full parent-child sub-incidents. Sub-incidents inherit services, environments, functionalities from parent. Each sub-team operates independently with shared context

**Gap**: No way to link related incidents. No parent/child. No merging.

**What this enables**: Coordinated response across teams for large incidents. Deduplication. Historical pattern recognition.

---

### 7. Tags / Labels → [INCIDENT_TAGS.md](INCIDENT_TAGS.md)

**Current**: None
**Needed**: Freeform or predefined tags for flexible categorization

- **incident.io**: Primarily uses incident types + custom fields for categorization
- **Rootly**: Tags as a custom field type. AI auto-tagging based on alert data

**Gap**: No tagging mechanism beyond what custom fields could provide.

**What this enables**: Quick categorization without rigid schemas. Cross-cutting concerns (e.g., "recurring", "customer-reported", "deploy-related").

---

### 8. Richer Status Updates → [INCIDENT_UPDATES.md](INCIDENT_UPDATES.md)

**Current**: Basic update flow with `next_update_at` reminder
**Needed**: Structured status updates as first-class records

- **incident.io**: Updates stored as records, posted to channel + announcement thread. AI drafts updates from timeline
- **Rootly**: Structured update forms per lifecycle stage. Communication plans with severity-based cadence

**Gap**: Status updates aren't persisted as their own records — they're just incident_events. No severity-based default cadence. No structured update history queryable independently.

**What this enables**: Update history timeline. "When was the last update?" queries. Compliance audit trails. Stakeholder notification preferences.

---

### 9. Incident Cancellation → covered in [INCIDENT_LIFECYCLE_STAGES.md](INCIDENT_LIFECYCLE_STAGES.md)

**Current**: No canceled state — only live → closed (resolved)
**Needed**: Ability to cancel/decline incidents (false positives, duplicates)

- **incident.io**: Triage incidents can be "Declined" — excluded from metrics
- **Rootly**: Explicit "Canceled" status — excluded from metrics

**Gap**: No way to mark an incident as a false positive without it counting as a resolved incident in metrics.

**What this enables**: Clean metrics. False positive tracking. Duplicate handling.

---

### 10. Configurable Forms per Lifecycle Phase → covered in [CUSTOM_FIELDS.md](CUSTOM_FIELDS.md) *(future)*

**Current**: Single creation modal, single update modal, single close modal
**Needed**: Different required/optional fields at each lifecycle transition

- **incident.io**: Configurable fields per form phase (create, accept, update, resolve)
- **Rootly**: Eight built-in forms (New, Update, Mitigation, Resolution, Cancellation, etc.) with custom sub-status forms

**Gap**: Same fields at every phase. No "require severity at creation but require summary at resolution" logic.

**What this enables**: Progressive data capture. Don't slow down triage with fields only needed at resolution.

---

## Summary — Prioritized for SMB Startups

**Must-have for schema flexibility** (build the tables/columns now, UI later):
1. Status lifecycle stages (add `triage` category + `canceled` concept)
2. Incident types
3. More timestamps (`acknowledged_at`, `mitigated_at`, per-status timestamps)
4. Custom field definitions table (not just JSONB)
5. Services / environments tracking

**Important but can be JSONB or simple FK initially**:
6. Related incidents (simple join table)
7. Tags/labels
8. Status updates as first-class records

**Can defer entirely**:
9. Parent/child sub-incidents (complex orchestration)
10. Configurable forms per phase (UI complexity)
11. AI auto-tagging / similarity matching
