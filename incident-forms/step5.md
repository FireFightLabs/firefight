# Step 5: Incident Form Rendering In Product Flows

Status: Planned

## Goal

Use the configured forms in actual incident flows.

## Scope

- render the `declare` form in incident creation flows
- render configured fields in update and resolve flows where applicable
- persist custom values through validated service paths
- expose the configured field values in incident detail views as appropriate

## Rendering Strategy

Render forms from serialized definitions, not hardcoded UI assumptions.

The frontend should receive:

- ordered fields
- field source type
- field metadata
- required and visibility configuration
- option data where needed

The renderer should be able to support:

- system fields
- fixed-option custom fields
- catalogue-backed fields

## Initial Flows

### Declare

This is the most important first integration.

Support:

- system incident inputs
- custom fields
- catalogue-backed references like affected services

### Update

Support a smaller form if configured.

### Resolve

Support closing metadata if configured.

## Display Strategy In Incident Detail

Custom field values should be visible in the incident detail experience in a way that preserves structure and readability.

Important:

- catalogue references should render as resolved entry names, not raw IDs
- multi-value fields should render cleanly
- absent values should degrade gracefully

## Backend Integration

`IncidentLifecycleService` should remain the write entry point.

The configured forms should influence what is accepted and what is required, but should not fragment the write model across multiple controllers or handlers.

## Acceptance Criteria

- incident create flow uses configured `declare` form
- configured custom fields persist correctly
- catalogue references resolve and render correctly
- update and resolve flows can consume configured form structures

## Notes For Later Steps

This step proves the product value of the forms system. After this, the model is ready for richer reporting and automation usage.
