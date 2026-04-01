# Step 4: Forms Settings UI And Form Editor

Status: Planned

## Goal

Build the settings UI for lifecycle forms and the editor for configuring which fields appear in each form.

## Scope

- add a `Forms` settings page
- show built-in lifecycle forms as cards
- build an editor for one form at a time
- allow reorder, show/hide, and required/optional configuration
- support adding reusable custom fields and catalogue-backed fields

## Product Shape

This is not a freeform page builder.

It is a structured form configuration tool with:

- predefined lifecycle forms
- one ordered field list per form
- simple configuration controls on each field row

## UX Direction

This should be one of the most polished admin surfaces in the product.

Inspiration:

- incident.io's forms area
- a composed control panel rather than a database editor

Desired qualities:

- clear overview cards for each form
- graceful transition into a focused form editor
- premium field rows with strong hierarchy
- reorder handles and inline metadata
- obvious distinction between system and custom fields
- subtle contextual guidance near the top of the editor

## Interaction Model

### Forms index

Show cards for:

- Declare
- Accept
- Update
- Resolve

Each card should include:

- name
- short description
- field count
- quick affordance to edit

### Form editor

Show:

- form header
- short explanatory copy
- ordered field list
- controls to reorder rows
- per-row visibility and required state
- badge for system or custom field
- field type and source details
- add-field action

### Reordering

Start with a simple and robust approach.

Acceptable first pass:

- move up/down controls
- optimistic row reordering

Optional richer pass:

- drag handle backed by a reliable sortable library

We should prefer correctness over flashy interactions.

## Backend Support

Needs:

- form serializers with ordered fields
- controller endpoints for reorder and configuration updates
- service methods for attaching/removing fields and reordering them

## Acceptance Criteria

- admins can browse built-in forms
- admins can configure a form's field order
- admins can show/hide fields in a form
- admins can mark fields required where allowed
- admins can add custom fields to a form
- UI quality feels intentional and production-grade

## Notes For Later Steps

This step builds the admin configuration surface. It does not yet wire the configured forms into incident creation and update flows.
