# Step 3: Admin UI For Custom Fields

Status: Planned

## Goal

Build the settings UI for reusable incident custom fields.

## Scope

- add a `Custom Fields` settings page
- list field definitions
- create and edit field definitions
- support catalogue-backed fields and fixed-option fields
- use a polished, production-grade settings experience

## UX Direction

This page should feel crisp and premium, with a layout closer to a high-quality product control surface than a generic CRUD table.

We want:

- strong hierarchy
- lightweight cards or rows with clear metadata
- calm spacing
- clear field type badges
- visible distinction between field type and option source
- tasteful empty states

The UI should preserve our product language while taking inspiration from incident.io's settings surfaces.

## Core UI Elements

### Field list

Each field should show:

- name
- key
- field type
- option source
- where it is used
- actions for edit/archive

### Creation and edit flow

Allow admins to configure:

- name
- description
- field type
- option source
- fixed options when relevant
- target catalogue type when relevant

### Supported first-pass option source flows

- `fixed`: simple option editor
- `catalog`: choose a catalogue type
- `none`: no option configuration required

## Frontend Design Guidance

Use a restrained, editorial admin aesthetic.

Recommended qualities:

- elegant typography hierarchy
- subtle section dividers
- card surfaces with deliberate density
- strong affordances on hover and focus
- clear state chips for field types and sources

Avoid:

- noisy table-heavy admin styling
- over-ornamented builder chrome
- generic gray-box settings UI

## Backend Support

This step depends on:

- field definition serializers
- controller actions for list/create/update/archive

Controllers should remain thin and delegate writes to services.

## Acceptance Criteria

- admins can create field definitions
- admins can edit supported field settings
- admins can create catalogue-backed fields
- field definitions render clearly and cleanly in settings UI

## Notes For Later Steps

This page manages reusable field definitions only. It does not configure which lifecycle form uses them.
