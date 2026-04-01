# Step 6: Reporting, Automation, And AI Readiness

Status: Planned

## Goal

Make the forms system useful beyond manual UI entry by exposing stable structures for reporting, automation, and future AI workflows.

## Scope

- expose custom field values cleanly in serializers and API responses
- support filtering and reporting on selected custom fields
- prepare stable read contracts for future MCP and AI integrations
- document how workflows can use form-backed incident metadata

## Reporting Direction

Once field definitions are structured, we can support:

- filtering incidents by custom field values
- exporting structured custom field data
- using catalogue-backed fields for grouped reporting

Examples:

- incidents by affected service
- incidents by environment
- incidents by customer tier

## Automation Direction

Structured incident fields can later drive:

- workflow triggers
- targeted notifications
- escalations based on field values
- post-incident process routing

## AI And MCP Readiness

The forms system should eventually support:

- agents reading field definitions to understand what information matters
- agents proposing or filling valid values
- MCP/API tools exposing valid field metadata and option sources

Important requirement:

AI clients should consume the same explicit field and form contracts as the frontend, not reverse-engineer values from raw JSON.

## Acceptance Criteria

- custom field values are exposed in stable serialized shape
- the field model is suitable for future filtering/reporting work
- documentation is clear on how forms and custom fields connect to automation and AI

## Completion Outcome

At the end of this step, incident forms should be a first-class domain capability rather than an isolated admin feature.
