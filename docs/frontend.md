# Frontend & Inertia Data Flow

Everything under `app/frontend/`, plus the serializer layer that feeds it. Read this before any frontend work or when adding/changing serializers.

## Stack

React 19 + TypeScript + Inertia.js (server-driven routing) + Vite + Tailwind CSS 4. UI primitives from shadcn/ui (Radix-based). Icons from `@tabler/icons-react`. Rich text editing with Tiptap.

## Serializers

`oj_serializers` serialize data for Inertia props (and eventually API responses). `types_from_serializers` auto-generates TypeScript interfaces from serializer definitions — no manual type maintenance.

```
app/serializers/                  # one serializer per Inertia prop shape; representative examples:
  base_serializer.rb              # Oj::Serializer + TypesFromSerializers::DSL, transform_keys :camelize
  incident_detail_serializer.rb     # Incident → incident detail page
  incident_list_item_serializer.rb  # Incident → dashboard list view
  timeline_event_serializer.rb      # IncidentEvent → timeline entries
  severity_option_serializer.rb     # IncidentSeverity → {name, slug}
```

**Generated TypeScript** lives in `app/frontend/types/serializers/` — auto-generated, never edit manually. Regenerate with `bundle exec rake types_from_serializers:generate`. In development, types regenerate automatically on serializer file changes.

**Generated constants** live in `app/frontend/lib/generated/constants.ts`, emitted by `bin/rails typescript:constants` from the list in `lib/typescript_constants.rb` (ability resources, alert operators and outcomes, webhook events, lifecycle stages, integration kinds). Never hand-copy a Ruby constant into TypeScript: add it to that list, regenerate, and keep any labels in TypeScript typed against the generated union (`Record<WebhookEvent, string>`) so a new value is a type error until it has a label. `test/lib/typescript_constants_test.rb` fails when the file is stale.

**Usage in controllers:**
```ruby
IncidentListItemSerializer.many(incidents)   # Array of hashes
SeverityOptionSerializer.many(severities)    # Array of hashes
```

**Adding a new serializer:**
1. Create `app/serializers/foo_serializer.rb` extending `BaseSerializer`
2. Use `attributes(name: {type: :string})` for pass-through fields with explicit types, or `type :string` + method definition for computed fields
3. Use `has_one`/`has_many` with `serializer:` for nested objects
4. Run `bundle exec rake types_from_serializers:generate` (or let dev mode auto-regenerate)
5. Import the generated type from `@/types/serializers` in frontend code

**When to use serializers vs raw hashes:**
- Model-backed data flowing to the frontend → serializer (auto-generates TS types)
- Simple computed value objects (pagination metadata, filter echo) → raw hash + manual TS types in module `types.ts`

## Dashboard (reference Inertia pattern)

The incidents dashboard demonstrates the full Inertia data flow pattern. Use it as a reference when building new dashboard-style pages.

**Data flow:**
```
Controller → Incident.filtered_list(filters:, page:, per_page:) → IncidentListItemSerializer.many(...)
           → DashboardStats.new(workspace).to_a (deferred)
           → SeverityOptionSerializer.many(...)
           ↓
Inertia props → usePage<DashboardPageProps>()
           ↓
Frontend    → useIncidentsTable(data, columns, filters, pagination) → router.get() on filter change
```

**Server-side filtering + pagination** (`Incident.filtered_list`):
- Accepts `filters: { search:, severities:, lifecycle_stages: }` hash (extensible) + `page:` + `per_page:`
- Chains model scopes: `search`, `by_severity_slugs`, `by_lifecycle_stage_keys`
- Returns `{ incidents:, pagination: { page, perPage, totalCount, totalPages } }`
- Eager-loads associations via `with_list_associations` scope to prevent N+1

**Deferred stats** (`DashboardStats` PORO):
- Wrapped in `InertiaRails.defer { ... }` — loads after initial page render so the table appears instantly
- Frontend uses `<Deferred data="stats" fallback={<StatCardsSkeleton />}>` for loading state
- Filter navigations use `only: ["incidents", "pagination", "filters"]` to skip re-fetching stats
- MTTR cached per workspace for 24h via `Rails.cache` (key: `dashboard_stats/{workspace_id}/mttr`)

**Frontend filter navigation** (`useIncidentsTable` hook):
- Filter/pagination changes call `router.get(dashboardPath(), params, { preserveState: true, preserveScroll: true, only: [...] })`
- Search input debounced 300ms before triggering navigation
- Severity/status toggles and page changes navigate immediately
- Column visibility and sorting remain client-side (within the current page)

**Key files:**
```
app/controllers/dashboard_controller.rb           # Thin — parses params, calls filtered_list, renders
app/models/incident.rb                            # filtered_list class method + filter scopes
app/models/dashboard_stats.rb                     # PORO for stat card metrics
app/serializers/incident_list_item_serializer.rb  # Serializes incidents → auto-generates TS type
app/serializers/severity_option_serializer.rb     # Serializes severity options → auto-generates TS type
app/frontend/pages/dashboard/hooks/               # useIncidentsTable — server-side filter navigation
app/frontend/pages/dashboard/components/          # Table, toolbar, pagination, stat cards + skeleton
app/frontend/types/serializers/                   # Auto-generated TS types (never edit manually)
app/frontend/pages/dashboard/types.ts             # Manual TS types (DashboardFilters, DashboardStat)
```

## Directory Structure

```
app/frontend/
  components/              # Cross-page shared components
    auth/                  # auth-layout, card-header, slack-button (used by login + onboarding)
    layout/                # App shell (authenticated-layout, theme-toggle)
    navigation/            # Sidebar, nav items, site header
    ui/                    # shadcn/ui primitives — NEVER modify directly
  pages/                   # Routes + co-located feature code
    dashboard/
      index.tsx            # /
      components/          # incidents-table, stat-cards, toolbar, pagination
      hooks/               # use-incidents-table
      lib/                 # constants, columns
      types.ts             # DashboardStat, DashboardFilters
    login/
      index.tsx            # /login
      components/          # terms-notice (login-only)
    incidents/
      index.tsx            # /incidents/:id
      postmortem.tsx       # /incidents/:id/postmortem
      components/
        index/             # incident-header, incident-timeline, action-panel, ... (detail page only)
        postmortem/        # postmortem-editor, ai-rewrite-dialog, revisions-sheet (postmortem page only)
      types.ts             # Re-exports Incident, IncidentAction, TimelineEvent from @/types/serializers
    catalogue/
      index.tsx            # /catalogue
      type.tsx             # /catalogue/:type_slug
      components/          # type-card, entry-table, sheets, form dialogs
      hooks/               # use-slack-data
      lib/                 # icon-map, constants
      types.ts             # CatalogType, AttributeDefinition, CatalogEntry
    settings/
      index.tsx            # /settings
      <tab>.tsx            # /settings/<tab>
      components/          # cross-tab shared (color-dot, row-actions)
        <tab>/             # one folder per settings tab; holds *-tab.tsx + its dialogs/sheets
      hooks/               # use-sync-form-data, use-permissions-matrix
      lib/                 # types.ts (data types; lives under lib/ to avoid colliding with types.tsx page)
    onboarding/
      <step>.tsx           # /onboarding/<step>
      components/          # permissions-dialog (install-only but onboarding-feature-shared)
      lib/                 # scope-permissions
  types/                   # Cross-page app-level types (SharedProps, Pagination)
    serializers/           # Auto-generated from oj_serializers — never edit by hand
  hooks/                   # Cross-page hooks (use-mobile)
  lib/                     # Cross-page utilities (routes, utils, formatters)
  entrypoints/             # Vite entrypoints (inertia.tsx, application.css)
```

## Rules

**Pages are thin routing shells:**
- The `index.tsx` (and any other top-level `.tsx`) in a `pages/<feature>/` folder is the entry point — it composes co-located components, receives props via `usePage<>()`, and sets `<Head>` title
- No business logic, no mock data defaults, no complex markup in pages
- Mock data fallbacks use `??` at the page level, never default props inside components

**One React component per file:**
- Each `.tsx` file contains exactly one React component (the file's default or named export).
- Types, helper functions, and constants used by that component stay in the same file.
- Substantial sub-components (anything with state, effects, or non-trivial JSX) move to their own file under `pages/<feature>/components/`. Pure render-only inline helpers under ~15 lines are still extracted for consistency.
- Filename matches the component name in kebab-case: `IncidentHeader` → `incident-header.tsx`, `PermissionsMatrix` → `permissions-matrix.tsx`.
- For a page that needs early-return-then-hooks, run all hooks first (use optional chaining when props might be null) and return the empty state branch *after* the hooks — don't split into wrapper + body.

**Page file paths mirror URL paths:**
- The base route of a namespace is `index.tsx`. Sub-routes use the static URL segment as the filename.
- When a route has only a dynamic segment (e.g. `/catalogue/:type_slug`), name the file after the singular resource being shown (`type.tsx`), not Rails actions (`show.tsx`) or bracket notation (`[slug].tsx`).
- Inertia resolves pages by string lookup against the `render inertia:` argument — keep the controller string in sync with the file path (`render inertia: "incidents/index"` → `pages/incidents/index.tsx`).
- Single-route top-level pages still get a folder for consistency (`pages/login/index.tsx`, not `pages/login.tsx`).
- Examples: `/` → `dashboard/index.tsx`, `/incidents/:id` → `incidents/index.tsx`, `/incidents/:id/postmortem` → `incidents/postmortem.tsx`, `/catalogue` → `catalogue/index.tsx`, `/catalogue/:type_slug` → `catalogue/type.tsx`.

**Page co-location:**
- Feature-specific code lives next to the route that owns it: `pages/<feature>/components/`, `pages/<feature>/hooks/`, `pages/<feature>/lib/`, `pages/<feature>/types.ts`
- No cross-page imports — `pages/dashboard/` must never import from `pages/incidents/`. If two pages need the same thing, lift it.
- **Lifting rules** (where it goes when ≥2 pages need it):
  - Shared UI → top-level `components/<topic>/` (e.g. `components/auth/` for the login + onboarding kit)
  - Shared types → top-level `types/` (e.g. `SharedProps`, `Pagination`); serializer-derived types are auto-generated into `types/serializers/`
  - Shared hooks → top-level `@/hooks/` (e.g. `use-mobile`)
  - Shared utils → top-level `@/lib/`
- **Hooks placement specifically:**
  - A hook used by exactly one feature lives in that feature's folder: `pages/<feature>/hooks/<name>.ts`.
  - A hook used by ≥2 features OR a generic primitive (`use-mobile`) lives at `app/frontend/hooks/`.
  - Don't keep file-local hooks inline in a component file — every hook is its own `.ts`, named `use-<kebab>.ts`.
- **Multi-page features group sub-components per page:**
  - When a feature has multiple page files (e.g. `pages/settings/` with one `.tsx` per tab), components used by exactly one page live in a subfolder named after that page: `pages/<feature>/components/<page>/<component>.tsx`.
  - Components shared by ≥2 pages within the feature stay flat at `pages/<feature>/components/` (e.g. `pages/settings/components/row-actions.tsx`, used by every settings tab).
  - Features with a single page (e.g. `pages/dashboard/`) keep the flat `components/` layout — no per-page subfolder needed.
- The Inertia resolver does a string lookup against `import.meta.glob('../pages/**/*.tsx')` so co-located components (anything other than the file the controller names) are inert — they're imported into the bundle but never resolved as a page.

**Every table sits in a `Card`:**
- The `Table` primitive draws no surface of its own. The container is always `Card` + `CardContent className="p-0"`, so the table runs edge to edge on the card background rather than on the page background.
- Anything scoped to the table (title, description, search, filters, the primary action) goes in `CardHeader`. Settings tabs put a `CardTitle`/`CardDescription` there; `catalogue/type.tsx` puts the search input there because the page header already carries the title.
- A card with no header takes `className="overflow-hidden py-0"` so the table fills it instead of floating inside the card's vertical padding — see `components/data-table.tsx` and `members-table.tsx`.
- Empty states follow the shape of the list: an in-table row for a filtered list that keeps its column headers, a plain padded `<CardContent>` for a list that is empty outright.
- Tables inside a `Dialog` or `Sheet` are the exception. The dialog is already an elevated surface, so they use `<div className="rounded-lg border overflow-hidden">` instead of a nested card.

## Configurable option lists (severities, statuses, types, roles)

These four settings tabs are one pattern, not four screens. Anything positioned,
soft-disableable and deletable-only-when-unused should join it rather than grow
its own table.

| Layer | Piece |
|---|---|
| Model | `ConfigurableOption`, plus `DefaultableOption` when one row is the workspace default, plus `NormalizedDescription` when the row has a description |
| Controller | `ManagesConfigurableOptions` supplies create/update/disable/enable/make_default/destroy/reorder |
| Serializer | `enabled`, `incidentCount`, and the `*BlockedReason` strings |
| Frontend | `OptionsTable` + `SortableOptionRow` + `OptionDialog`, all flat in `pages/settings/components/` |

**Guard rules live on the model, once.** `deletion_blocked_reason`,
`disable_blocked_reason` and `default_blocked_reason` return a sentence or nil.
The controller turns one into a flash alert, the serializer ships it, and the row
renders it as a tooltip on the disabled control. Never re-derive a rule in the
controller or the frontend: a boolean like `deletable` drifts from what the
controller actually enforces, which is exactly what these replaced.

**Counts come from `with_usage_counts`**, one correlated subquery per page. A
model whose blocking association is not `incidents` overrides `usage_association`
(roles block on `incident_role_assignments`).

**Colour and default are capabilities, not flags.** A list without a `color`
column gets no colour field; a model that omits `DefaultableOption` gets no
Default column and no radio group.

**Descriptions are normalized on save, not at render.** `NormalizedDescription`
capitalizes a first word that is entirely lowercase and terminates the sentence
before validation. This exists because Slack rewrites what we send it: an
`input` block's `hint` gains a trailing period when it has none, and keeps the
one it has. That behaviour is undocumented but consistent, so a description
typed as "limited impact" reaches Slack as "Limited impact." while the dashboard
and the API keep showing the raw string. Normalizing in the model makes Slack's
rewrite a no-op and keeps every surface identical. Fixing it per-surface would
mean patching Slack, Inertia, the REST API and the MCP tools separately and
still leave the stored value inconsistent.

The capitalization guard only protects a first word that carries its own case,
so `iOS` and `eBay` survive but an all-lowercase tool name like `kubectl` is
capitalized. That is the accepted trade-off, not an oversight.

**shadcn/ui components are untouched:**
- Never modify files in `components/ui/` — they may be updated by `npx shadcn` later
- Wrap or compose shadcn components if you need custom behavior
- ESLint ignores `components/ui/` for this reason
- Prefer shadcn/ui components when one exists for your use case; write a custom component only if shadcn doesn't have it

**Type discipline:**
- No `Record<string, string>` when a tighter type exists — use typed keys from const arrays
- Flexible schemas (catalogue attributes) key by stable `key`/`slug`, never by mutable display `name`
- Attribute keys are immutable once set — auto-generate from name only for new attributes (empty key), never overwrite existing keys during edit
- Reference fields store entry IDs, not display labels — resolve at render time via `resolveReference()` or equivalent
- Use `Pick<>` from shared types instead of redefining inline shapes
- Page props are typed via `usePage<InterfaceName>()`
- Page-prop interfaces must `extend SharedProps` (from `@/types`). `SharedProps` intersects with Inertia's `PageProps` so the index-signature constraint is satisfied; bare `interface Foo { ... }` fails the `usePage<T extends PageProps>` constraint in strict mode. Name them `<Resource>PageProps` (e.g. `DashboardPageProps`, `CatalogueTypePageProps`).

**Dependency direction:**
- The page entry-point file (`index.tsx` / sibling `.tsx`) owns data flow; its co-located components/hooks/lib are leaves it composes
- Co-located components receive data as props — never import mock data or lookup functions directly
- Lookup helpers (e.g., `getTypeById`, `resolveReference`) are acceptable in leaf display components but all available options (e.g., list of types for a dropdown) must be passed as props from the page level
- Search/filter logic in components should resolve references before matching (users search by display name, not stored IDs)

**Data flow:**
- Controllers send typed Inertia props → page entry-point receives via `usePage<>()` → passes to co-located components
- Components receive data as required props — no internal mock fallbacks
- Mock data lives in `pages/<feature>/lib/mock-data.ts` and is only imported by the page entry-point
- Lookup/resolver functions (e.g., `resolveReference()`) are called at render time, not stored in data

**Imports use the `@/` alias only:**
- Never `./` or `../` in `app/frontend/`. Always `@/components/...`, `@/pages/...`, `@/hooks/...`, `@/lib/...`, `@/types`. The alias resolves to `app/frontend/` (configured in `tsconfig.app.json` + root `tsconfig.json`).
- Exception: gem-generated files in `types/serializers/` use relative imports — leave them alone, they're regenerated by `types_from_serializers`.

**Component patterns:**
- React hooks and types are named imports — `import { useState, useEffect, type ReactNode } from "react"`. Never `import * as React from "react"` + `React.useState(...)`. The only exception is files inside `components/ui/` (shadcn primitives, untouched).
- Dynamic icon selection uses a `<ComponentName>` component, not a function returning a component
- `useCallback` for functions passed to memoized children or returned from hooks
- `useMemo` for derived/filtered data

**Naming conventions:**
- Components: `PascalCase` (`IncidentsTable`, `StatCards`)
- Files: `kebab-case` (`incidents-table.tsx`, `stat-cards.tsx`)
- Types: `PascalCase` (`IncidentListItem`, `DashboardStat`)
- Constants: `UPPER_SNAKE_CASE` (`SEVERITY_OPTIONS`, `STATUS_LABELS`)
- Hooks: `camelCase` with `use` prefix (`useIncidentsTable`)
- Feature/page directories: `kebab-case` (`dashboard`, `incidents`, `catalogue`)

**Navigation:**
- Sidebar sections: "Respond" (Incidents), "Configure" (Catalogue, Integrations, Settings)
- Active page determined by URL match
- Inertia `<Link>` for SPA navigation, `<a>` only for external links
- Route helpers from generated `@/lib/routes` (e.g., `dashboardPath()`, `incidentPath(id)`)

## Tooling

- `npm run typecheck` — TypeScript strict check (`tsc -b --noEmit`). Uses `-b` because the root `tsconfig.json` is a project-references file; plain `tsc --noEmit` silently skips the referenced projects.
- `npm run lint` — ESLint with TypeScript + React Hooks plugins
- `npm run lint:fix` — auto-fix lint issues
- Both must pass clean before any PR
- ESLint config: `eslint.config.js` (flat config, ignores `components/ui/` and generated routes)

## Theme

Dark navy theme with cyan primary accent. Colors defined as CSS custom properties in `application.css` using oklch. Both light and dark themes supported via `.dark` class toggle.

- Background hue: 255 (navy blue tint, not pure gray)
- Primary: hue 195 (cyan/teal)
- Chroma on dark backgrounds: 0.035 (visibly blue, not grayish)
