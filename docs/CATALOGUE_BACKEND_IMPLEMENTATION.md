# Catalogue Backend Implementation

## Context

Firefight already has a catalogue UI shell, but the backend domain has not been built yet. We need to make the catalogue fully functional as a backend system before wiring it into incident forms and other product surfaces.

The catalogue needs to support two things at the same time:

- first-class system entities that Firefight understands semantically
- workspace-defined custom entities that users can add for their own modeling needs

This doc focuses on the backend domain only.

UI wiring into incident creation, incident update, Slack modals, and admin settings is explicitly out of scope for this phase.

## Decision

Build the catalogue as a shared generic backend with reserved system types.

That means:

- one catalogue infrastructure for types, entries, attributes, and relationships
- seeded system types per workspace
- support for additional custom types created by workspace admins
- strong backend rules around reserved system semantics

This replaces the earlier direction in `docs/SYSTEM_CATALOG.md` that proposed separate top-level tables per entity type.

## Goals

- Support seeded system types: `service`, `team`, `environment`, `functionality`
- Support custom workspace-defined catalogue types
- Support typed attributes on catalogue types
- Support catalogue entries scoped to a workspace
- Support entry-to-entry relationships that are queryable and validated
- Support serialization for the existing catalogue pages
- Keep the backend compatible with future incident integration, routing, and automation

## Non-goals

- Wiring catalogue fields into incident creation or update flows
- Building incident field configuration
- Building custom incident fields
- Adding Slack-specific catalogue UX
- Adding workflow automation behavior driven by catalogue data

## Why This Shape

We need Firefight to understand some entities semantically.

Examples:

- incidents should later be able to reference affected services and environments
- integrations should later be able to target a `service` or `environment`
- routing and ownership should later be able to understand `team` and `functionality`

At the same time, users will need additional entities Firefight does not know about ahead of time.

Examples:

- `vendor`
- `customer`
- `dependency`
- `region`
- `runbook`

So the right model is not:

- only fixed tables for system entities
- or only a completely generic schema with no system meaning

The right model is:

- generic storage and validation
- explicit reserved system types with product meaning

## Core Model

### `CatalogType`

Workspace-scoped entity type definition.

Suggested columns:

```ruby
create_table :catalog_types, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug, null: false
  t.string :kind, null: false # system | custom
  t.string :system_key # service | team | environment | functionality
  t.string :icon
  t.text :description
  t.string :color
  t.integer :position, null: false
  t.datetime :deleted_at
  t.timestamps
end

add_index :catalog_types, [ :workspace_id, :slug ], unique: true
add_index :catalog_types, [ :workspace_id, :system_key ], unique: true,
  where: "system_key IS NOT NULL"
```

Rules:

- `slug` is the stable identifier
- `kind` is `system` or `custom`
- `system_key` is required for system types and null for custom types
- reserved system slugs cannot be used by custom types
- system types are soft-deletable only if we later explicitly allow that; for now they should be protected from deletion

Reserved system keys:

- `service`
- `team`
- `environment`
- `functionality`

### `CatalogAttributeDefinition`

Schema definition for entries of a given type.

Suggested columns:

```ruby
create_table :catalog_attribute_definitions, id: :uuid do |t|
  t.references :catalog_type, type: :uuid, null: false, foreign_key: true
  t.string :key, null: false
  t.string :name, null: false
  t.string :attribute_type, null: false
  t.boolean :required, null: false, default: false
  t.integer :position, null: false
  t.jsonb :config, null: false, default: {}
  t.timestamps
end

add_index :catalog_attribute_definitions, [ :catalog_type_id, :key ], unique: true,
  name: "index_catalog_attribute_definitions_on_type_and_key"
```

Supported attribute types for v1:

- `text`
- `number`
- `boolean`
- `select`
- `list`
- `reference`

Config examples:

```json
{ "options": ["Critical", "Standard", "Internal"] }
```

```json
{ "reference_type_id": "uuid" }
```

Rules:

- attribute values are stored on entries keyed by stable `key`, never by display `name`
- existing keys are immutable after creation
- type-specific config is validated by the backend

### `CatalogEntry`

An instance of a catalogue type.

Suggested columns:

```ruby
create_table :catalog_entries, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.references :catalog_type, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.string :slug, null: false
  t.jsonb :attributes, null: false, default: {}
  t.datetime :deleted_at
  t.timestamps
end

add_index :catalog_entries, [ :catalog_type_id, :slug ], unique: true
add_index :catalog_entries, [ :workspace_id, :catalog_type_id ]
```

Rules:

- every entry belongs to both a workspace and a catalog type
- `slug` is a stable identifier within the type
- `attributes` stores scalar values keyed by attribute `key`
- reference attributes store target entry ids, not names

### `CatalogEntryRelationship`

Query-friendly relationship layer between entries.

Suggested columns:

```ruby
create_table :catalog_entry_relationships, id: :uuid do |t|
  t.references :workspace, type: :uuid, null: false, foreign_key: true
  t.references :source_entry, type: :uuid, null: false, foreign_key: { to_table: :catalog_entries }
  t.references :target_entry, type: :uuid, null: false, foreign_key: { to_table: :catalog_entries }
  t.string :relationship_type, null: false
  t.integer :position
  t.timestamps
end

add_index :catalog_entry_relationships,
  [ :source_entry_id, :target_entry_id, :relationship_type ],
  unique: true,
  name: "index_catalog_entry_relationships_uniqueness"
```

This exists because important catalogue relationships are not always well represented as a single scalar attribute.

Examples:

- one functionality depends on many services
- one service may be deployed to many environments
- a team may own many services

Storing these as first-class rows is better than burying all of them inside jsonb.

## Workspace Associations

Add to `Workspace`:

```ruby
has_many :catalog_types, dependent: :destroy
has_many :catalog_entries, dependent: :destroy
```

## System Types

Seed these per workspace during workspace setup.

### `team`

Default attributes:

- `description` text
- `slack_channel` text
- `manager` text
- `members` list

### `service`

Default attributes:

- `description` text
- `owner_team` reference to `team`
- `tier` select
- `repository` text
- `slack_channel` text

### `environment`

Default attributes:

- `description` text
- `is_production` boolean
- `region` text

### `functionality`

Default attributes:

- `description` text
- `owner_team` reference to `team`

Important note:

Relationships like functionality-to-service should live in `catalog_entry_relationships`, not only in scalar attributes.

## Backend Validation Rules

Validation should live primarily in service objects, with model-level validations handling simple invariants.

### Type-level rules

- name required
- slug required and unique per workspace
- system keys unique per workspace
- custom types cannot use reserved system slugs
- system types cannot change `slug` or `system_key`
- system types cannot be deleted in v1

### Attribute definition rules

- `key` required and unique per type
- `key` immutable after create
- `attribute_type` must be one of the supported constants
- `select` requires non-empty `options`
- `reference` requires valid `reference_type_id`

### Entry rules

- name required
- slug required and unique within type
- entry workspace must match type workspace
- required attributes must be present
- unknown attribute keys rejected
- select values must be in configured options
- number fields must be numeric
- boolean fields must be boolean
- list fields must serialize to arrays
- reference values must point to existing entries in the referenced type within the same workspace

### Relationship rules

- source and target entries must belong to the same workspace
- relationship type required
- duplicate relationships rejected
- self-references allowed only if explicitly supported; default is reject

## Service Layer

Use service objects for all catalogue writes.

Suggested services:

- `Catalogue::SeedDefaults`
- `Catalogue::CreateType`
- `Catalogue::UpdateType`
- `Catalogue::DeleteType`
- `Catalogue::CreateEntry`
- `Catalogue::UpdateEntry`
- `Catalogue::DeleteEntry`
- `Catalogue::SyncRelationships`

This follows the existing app pattern of keeping controllers thin and business rules in services.

## Read Path

The existing catalogue pages should be backed by real serialized data.

### `CatalogueController#index`

Should render:

- all active types in the workspace
- entry counts per type

### `CatalogueController#show`

Should render:

- selected type by slug
- entries for that type
- enough reference metadata for the frontend to display related labels without mock helpers

## Serialization

Add serializers for:

- `CatalogAttributeDefinitionSerializer`
- `CatalogTypeSerializer`
- `CatalogEntrySerializer`

These should generate the frontend types instead of relying on mock-only TypeScript interfaces over time.

## API and Controller Surface

For the backend-first phase, build the Rails surfaces needed to make catalogue fully functional.

Suggested routes:

- `GET /app/catalogue`
- `GET /app/catalogue/:type_slug`
- `POST /app/catalogue/types`
- `PATCH /app/catalogue/types/:id`
- `DELETE /app/catalogue/types/:id`
- `POST /app/catalogue/types/:type_id/entries`
- `PATCH /app/catalogue/entries/:id`
- `DELETE /app/catalogue/entries/:id`

Controllers should remain thin and delegate to services.

## How This Fits the Rest of Firefight

This backend is intentionally designed to support future product work without forcing that work into this first implementation phase.

### Incident management

Later, incidents should be able to link to catalogue entries through a dedicated join table such as:

```ruby
create_table :incident_catalog_entries, id: :uuid do |t|
  t.references :incident, type: :uuid, null: false, foreign_key: true
  t.references :catalog_entry, type: :uuid, null: false, foreign_key: true
  t.timestamps
end
```

That should be built after the catalogue backend itself is complete.

### Incident field configuration

Later, field visibility for create/update/close should live in a separate incident form configuration layer, not on the catalogue type itself.

### Integrations and automation

System catalogue types provide stable target semantics for future integrations:

- `service`
- `team`
- `environment`
- `functionality`

Custom types remain available for future extensibility.

## Delivery Order

1. Schema and models
2. Seed system catalogue types
3. Service layer for type and entry writes
4. Serializers and read path for existing catalogue pages
5. Write controllers and tests
6. Replace frontend mock read paths

Detailed ticket breakdown lives in `docs/CATALOGUE_BACKEND_TICKETS.md`.
