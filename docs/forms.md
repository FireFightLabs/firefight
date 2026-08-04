# Incident forms

The dialogs responders fill in at each lifecycle moment: Declare, Update,
Resolve, Cancel. One system feeds two surfaces, and most bugs here come from
forgetting that.

## The two surfaces

| | Reads | Shows |
|---|---|---|
| **Slack modal** | `resolve(slug, context:)` | only what a responder should fill in |
| **Settings → Forms** | `resolve(slug, include_hidden: true)` | everything an admin can configure |

**The editor must be able to reach everything it can configure.** This is the
rule that has been broken three times: hidden fields vanished from the editor,
so a hidden field could never be unhidden; `available` fields were dropped
entirely, so they could never be enabled. If a field can be turned on, the
editor has to render it turned off. A capability that cannot be reached does
not exist.

Corollary: **a field is never absent because it is off.** Absent means "cannot
apply here at all". Off means "applies, but not right now".

## Where a field comes from

- **`IncidentSystemField::DEFINITIONS`** is the code registry: built-in fields
  (name, severity, status, summary, message, …), which forms each appears on,
  and how it ships. No migration to add one.
- **`incident_field_definitions`** are workspace-defined custom fields.
- **`incident_form_fields`** rows are **overlays only**. A row exists because
  someone customized something. No row means "use the code default".

`IncidentFormResolver#resolve` merges: walk the registry defaults for the slug,
swap in an override where a row exists, drop hidden ones unless
`include_hidden`, append custom fields, sort by position.

## How a system field ships

The registry's `forms:` map says both *whether* a field belongs on a form and
*how it arrives*:

| Value | Editor | Slack |
|---|---|---|
| `optional` / `required` | shown, on | shown |
| `fixed_required` | shown, both toggles locked | always shown |
| `available` | shown, **off** | hidden until enabled |
| absent from the map | not shown | never |

`available` is not a stored value. On the row it becomes
`visibility_mode: hidden` + `required_mode: optional`. Both
`IncidentFormResolver#default_form_field` and
`IncidentFormService#ensure_system_field!` do that mapping, and they must agree.

## Synthetic ids

A system field with no override row has no database id, so the serializer gives
it `default:<key>` and marks `isDefault`. Editing one **materializes the row**
via `ensure_system_field!`, which is why `PATCH` accepts a synthetic id and
needs `incident_form_id` alongside it. Same trick as `resolve_form` for a form
that has no row yet.

## Rules that are enforced, and where

- **`locked_visible?` / `locked_required?`** live on `IncidentFormField`.
  Severity and Status are `NOT NULL` on incidents, so hiding either produces a
  form that can never submit. Enforced in `IncidentFormService#update_field`,
  not just disabled in the UI.
- **Status on a terminal form** is scoped to the statuses in the stage that
  transition targets, so nobody can resolve an incident into Investigating.
  It is omitted entirely when that stage holds fewer than two statuses, because
  one option is not a choice.
- **Message** writes to `incident_updates.message`, not an incident attribute.
  It is the only system field that does, so `validate_submission` returns it in
  `system_attrs` and the handler reads it from there.

## Copy lives in the registry

`label`, `hint`, and `placeholder` are on the definition, and **both** the
Slack block builders and the editor preview read them. They used to be
hardcoded in `field_blocks.rb`, which is how the editor ended up previewing
words responders never saw. `name` is separate and is for prose: flash
messages, "Severity is required", the settings row.

## Adding a system field

1. Add a `Definition` to `IncidentSystemField::DEFINITIONS` with `label`,
   `hint`, `placeholder`, and its `forms:` map.
2. Add a block builder branch in `FieldBlocks.build_system`.
3. Confirm both surfaces: `resolve(slug)` and
   `resolve(slug, include_hidden: true)`.

No migration, no seeding.
