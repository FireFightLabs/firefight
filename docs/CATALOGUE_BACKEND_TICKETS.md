# Catalogue Backend Tickets

This document breaks down `docs/CATALOGUE_BACKEND_IMPLEMENTATION.md` into implementation tickets.

Goal of this phase:

- make the catalogue backend fully functional
- support both reserved system entities and custom workspace-defined entities
- back the existing catalogue pages with real data
- stop before incident form integration

Related docs:

- architecture and backend design: `docs/CATALOGUE_BACKEND_IMPLEMENTATION.md`
- previous system-catalog direction: `docs/SYSTEM_CATALOG.md`

## Ticket 1: Core Schema

Create the base catalogue schema.

Scope:

- add `catalog_types`
- add `catalog_attribute_definitions`
- add `catalog_entries`
- add `catalog_entry_relationships`
- add indexes and foreign keys

Acceptance criteria:

- all four tables exist with workspace scoping
- unique indexes protect `slug`, `key`, and relationship uniqueness
- schema supports soft deletion on types and entries
- relationship rows point to `catalog_entries`

## Ticket 2: Core Models and Associations

Add Rails models and workspace associations.

Scope:

- add `CatalogType`
- add `CatalogAttributeDefinition`
- add `CatalogEntry`
- add `CatalogEntryRelationship`
- wire associations from `Workspace`
- add active and ordered scopes

Acceptance criteria:

- models load and associate correctly
- workspace scoping is explicit
- simple validations exist for required columns

## Ticket 3: Seed Reserved System Types

Seed system catalogue types per workspace.

Scope:

- add catalogue default seeding during workspace setup
- seed `service`, `team`, `environment`, `functionality`
- seed default attribute definitions for each system type

Acceptance criteria:

- a newly created workspace gets all four system types
- system types have stable `system_key` and reserved `slug`
- seed is idempotent for existing workspaces

## Ticket 4: Type Write Services

Implement service-layer writes for catalogue types.

Scope:

- create type service
- update type service
- delete type service
- support nested attribute definition writes
- enforce reserved system type rules

Acceptance criteria:

- custom types can be created, updated, and soft-deleted
- system types cannot have `slug` or `system_key` changed
- system types cannot be deleted
- existing attribute keys remain stable across updates

## Ticket 5: Entry Write Services

Implement service-layer writes for catalogue entries.

Scope:

- create entry service
- update entry service
- delete entry service
- validate jsonb-backed attributes against attribute definitions

Acceptance criteria:

- required fields are enforced
- select values are validated against options
- reference values are validated against referenced type entries
- unknown attribute keys are rejected
- entries are soft-deleted instead of destroyed

## Ticket 6: Relationship Write Services

Implement entry relationship writes.

Scope:

- add relationship sync service or equivalent write path
- support creation and removal of relationships per entry update
- validate workspace consistency and duplicate protection

Acceptance criteria:

- relationships can be added and removed safely
- duplicate edges are rejected
- source and target entries must belong to the same workspace

## Ticket 7: Serializers

Add serializers for catalogue data returned to Inertia.

Scope:

- add `CatalogAttributeDefinitionSerializer`
- add `CatalogTypeSerializer`
- add `CatalogEntrySerializer`
- include fields needed by the existing frontend pages

Acceptance criteria:

- serializer output matches backend contract for the catalogue pages
- generated frontend types can replace mock-only assumptions over time

## Ticket 8: Catalogue Read Path

Back the existing catalogue pages with real data.

Scope:

- update `CatalogueController#index`
- update `CatalogueController#show`
- preload data needed for reference display and entry counts

Acceptance criteria:

- index page returns workspace types with counts
- show page returns the selected type and its entries
- pages can render without relying on backend mock fallbacks

## Ticket 9: Catalogue Write Controllers

Add thin controllers and routes for catalogue writes.

Scope:

- add routes for type CRUD
- add routes for entry CRUD
- controllers delegate to services
- controllers return redirects or inertia-friendly responses

Acceptance criteria:

- type and entry writes go through services only
- no business logic lives in controllers
- failure cases are surfaced cleanly

## Ticket 10: Tests

Add backend test coverage for the catalogue domain.

Scope:

- model tests for basic invariants
- service tests for type, entry, and relationship writes
- controller tests for read paths
- controller or request tests for write flows as appropriate

Acceptance criteria:

- system type protection is covered
- entry validation behavior is covered
- reference validation is covered
- read paths are covered

## Ticket 11: Replace Mock Read Path

Stop using frontend mock data for catalogue page reads.

Scope:

- remove page-level mock fallback for server-provided catalogue data
- keep any temporary frontend write placeholders isolated until UI write wiring is done

Acceptance criteria:

- catalogue pages render from real backend data
- missing-type and empty-state behavior still works cleanly

## Ticket 12: Follow-up Doc for Incident Integration

Create the next design doc after catalogue backend lands.

Scope:

- define incident field configuration for catalogue-backed incident fields
- define create/update/close visibility rules
- define incident-to-catalogue join model

Acceptance criteria:

- follow-up doc is separate from catalogue backend implementation
- it treats incident form behavior as incident configuration, not catalogue schema

## Recommended Delivery Sequence

1. Ticket 1
2. Ticket 2
3. Ticket 3
4. Ticket 4
5. Ticket 5
6. Ticket 6
7. Ticket 7
8. Ticket 8
9. Ticket 9
10. Ticket 10
11. Ticket 11
12. Ticket 12
