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
- **A field with no possible answer is dropped**, by
  `IncidentFormResolver#unanswerable_reason`. Three cases today: Status on a
  terminal form whose stage holds a single status (the transition sets it
  anyway), Incident Type in a workspace with no types, and a select or catalog
  custom field with nothing to pick. Each is dropped from `resolve(slug)` and
  kept under `include_hidden` carrying the sentence saying why, which the
  serializer ships as `inactive_reason`. A field that appears in Slack without
  appearing in configuration is inexplicable, and so is the reverse.

  **This must live in the resolver, never in a block builder.**
  `validate_submission` reads the same `resolve(slug)`, so a field suppressed
  only at render is still demanded on submit: the modal names a field it never
  showed and can never be submitted. That shipped once. It was reachable the
  moment an admin touched Status in the editor, because materializing the
  overlay row moved the field onto a code path that skipped the check.
  `unanswerable_reason` now runs against the merged field, override or default,
  so there is one path and no way back in.

  The proof that the resolver is authoritative: the modals `map` over the
  resolved set. Nothing downstream filters, so nothing downstream can disagree.

- **A field the answers so far have made pointless is dropped**, by
  `IncidentFormResolver#moot_for_context?`. One case today: Next Update on the
  update form once the picked status is terminal, since a closed or canceled
  incident is not waiting on anything and `Incident::Lifecycle` clears
  `next_update_at` for a terminal stage regardless.

  Distinct from `unanswerable_reason`, and deliberately not merged with it.
  That one is about how the workspace is configured, holds across a whole
  session, and carries a sentence the editor shows. This one reads what the
  responder just picked, changes between one submission and the next, and must
  never reach the editor: the field is configured and does apply, just not to
  this answer. So it sits with the condition match, after the
  `return merged if include_hidden` that the editor stops at.

  It is subject to the same rule as `unanswerable_reason`: it lives in the
  resolver because `validate_submission` reads the same `resolve(slug)`.
  `Slack::FormSubmission` already builds its context from the *submitted*
  status, so a modal that never got the refresh still submits cleanly rather
  than failing on a field the form no longer asks for.

- **The update modal's Status select dispatches**
  (`Identifiers::INCIDENT_UPDATE_STATUS_SELECT`), so picking a terminal status
  re-renders the modal through `Interactions::IncidentUpdateSelectHandler`
  without the Next Update timer. A dispatching select must be handed its own
  pick back as `initial_option` (`selected_status_slug:`), or the re-render
  snaps it to the value the incident still holds. Severity, Incident Type and
  Visibility on the declare modal all do the same.
- **Status on a terminal form** is scoped to the statuses in the stage that
  transition targets, so nobody can resolve an incident into Investigating.
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
2. Add a block builder branch in `FieldBlocks.build_system`. It renders
   unconditionally. If the field can have nothing to ask, that belongs in
   `unanswerable_reason`, with the sentence a reader will see in the editor. If
   it is another answer on the same form that makes it pointless, that belongs
   in `moot_for_context?` instead, and the editor keeps showing it.
3. Confirm both surfaces: `resolve(slug)` and
   `resolve(slug, include_hidden: true)`.

No migration, no seeding.
