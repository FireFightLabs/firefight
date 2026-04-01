# Step 2: Services, Validation, And Persistence

Status: Planned

## Goal

Add the write-path orchestration and validation layer that turns form definitions into trusted incident writes.

## Scope

- create services for managing field definitions and forms
- validate incident submissions against active form configuration
- normalize values before persistence
- keep controllers thin
- integrate with `IncidentLifecycleService`

## Service Design

### Admin write services

Add service objects for:

- `IncidentFieldDefinitionService`
- `IncidentFormService`

Responsibilities:

- create and update definitions
- protect immutable fields
- validate option-source config
- reorder form fields
- add or remove fields from forms

### Submission service

Add either:

- `IncidentFormSubmissionService`

or a small, well-contained collaborator used by `IncidentLifecycleService`.

Responsibilities:

- resolve the applicable form for a lifecycle action
- determine visible and required fields
- validate incoming values
- split system-field values from custom-field values
- validate catalogue references
- normalize final payload for persistence

## Validation Rules

### System fields

Validate built-in fields according to incident domain rules.

Examples:

- severity must resolve to an active severity
- incident type must resolve to an active type if provided
- status must resolve to an allowed status in the relevant flow

### Custom fields

Validate according to `IncidentFieldDefinition`.

Examples:

- text is string-like
- number is numeric
- single-select must be one of fixed options
- multi-select values must all be in fixed options
- catalogue reference must resolve to an active catalogue entry of the configured type

### Unknown field rejection

Reject fields not present in the resolved form.

This is important for safety and consistency across UI, API, and future AI clients.

## Persistence Shape

Persist:

- system field values to first-class `Incident` columns
- custom values to `incident.custom_fields`

This preserves the current storage direction while adding structure around it.

## Integration With Incident Lifecycle

`IncidentLifecycleService` should remain the single source of truth for incident writes.

Pattern:

- entry point normalizes request
- lifecycle service calls form submission validator
- lifecycle service applies validated attrs
- snapshots and events continue to capture `custom_fields`

## Tests

Add tests for:

- field definition service create/update/delete
- form service create/update/reorder
- submission validation for each supported field type
- catalogue-backed field resolution
- unknown field rejection
- required field enforcement
- transaction rollback on invalid submissions

## Acceptance Criteria

- service layer owns write orchestration
- incident writes can validate against form configuration
- catalogue-backed field submissions are validated correctly
- `custom_fields` persistence is structured and tested

## Notes For Later Steps

This step should not include the full admin UX. It is about correctness and service boundaries.
