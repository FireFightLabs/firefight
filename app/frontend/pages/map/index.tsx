import { Head, Link, router, usePage } from "@inertiajs/react"
import { IconRefresh, IconSearch, IconTopologyStar3 } from "@tabler/icons-react"
import { useCallback, useMemo, useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { RESOURCE_MAP_KINDS } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { integrationsPath, resourceMapSyncPath } from "@/lib/routes"
import { AddLinkDialog } from "@/pages/map/components/add-link-dialog"
import { AttentionPanel } from "@/pages/map/components/attention-panel"
import { MapCanvas } from "@/pages/map/components/map-canvas"
import { ResourcePanel } from "@/pages/map/components/resource-panel"
import { ResourceTable } from "@/pages/map/components/resource-table"
import { linksAmong, matchesFilters, neighborhood } from "@/pages/map/lib/graph"
import { KIND_LABELS } from "@/pages/map/lib/labels"
import { timeAgo } from "@/pages/map/lib/time"
import {
  DEPTHS,
  type Depth,
  type Direction,
  DIRECTIONS,
  MAP_QUERY,
  MAP_VIEWS,
  type MapFilters,
  type MapPageProps,
  type MapView,
} from "@/pages/map/types"
import type { ResourceMapResource } from "@/types/serializers"

const ALL = "all"
const DEFAULT_DEPTH: Depth = 2
const CANVAS_HEIGHT = "h-[calc(100dvh-13rem)] min-h-[28rem]"

const VIEW_LABELS: Record<MapView, string> = { map: "Map", focus: "Focus", table: "Table" }
const DIRECTION_LABELS: Record<Direction, string> = { both: "Both ways", needs: "What it needs", needed_by: "What needs it" }

function fromUrl(): { view: MapView; resourceId: string | null } {
  const params = new URLSearchParams(window.location.search)
  const view = Object.values(MAP_VIEWS).find((each) => each === params.get(MAP_QUERY.VIEW)) ?? MAP_VIEWS.MAP
  return { view, resourceId: params.get(MAP_QUERY.RESOURCE) }
}

export default function ResourceMapPage() {
  const { resources, links, connections, changes, catalogEntries, readsIn } = usePage<MapPageProps>().props
  const canCurate = useCan("catalog")
  const canSync = useCan("integrations")
  const [ place, setPlace ] = useState(fromUrl)
  const [ filters, setFilters ] = useState<MapFilters>({ query: "", environment: null, provider: null, kind: null })
  const [ depth, setDepth ] = useState<Depth>(DEFAULT_DEPTH)
  const [ direction, setDirection ] = useState<Direction>(DIRECTIONS.BOTH)
  const [ adding, setAdding ] = useState(false)

  const go = useCallback((view: MapView, resourceId: string | null) => {
    setPlace({ view, resourceId })
    const params = new URLSearchParams(window.location.search)
    params.set(MAP_QUERY.VIEW, view)
    if (resourceId) {
      params.set(MAP_QUERY.RESOURCE, resourceId)
    } else {
      params.delete(MAP_QUERY.RESOURCE)
    }
    window.history.replaceState(null, "", `${window.location.pathname}?${params.toString()}`)
  }, [])

  const shown = useMemo(() => resources.filter((resource) => matchesFilters(resource, filters)), [ resources, filters ])
  const shownLinks = useMemo(() => linksAmong(links, new Set(shown.map((resource) => resource.id))), [ links, shown ])
  const ranked = useMemo(() => [ ...resources ].sort((first, second) => second.dependentIds.length - first.dependentIds.length), [ resources ])
  const focused = resources.find((resource) => resource.id === place.resourceId) ?? ranked[0] ?? null

  function focusOn(resourceId: string) {
    go(MAP_VIEWS.FOCUS, resourceId)
  }

  function switchView(value: string) {
    const view = Object.values(MAP_VIEWS).find((each) => each === value)
    if (view) {
      go(view, view === MAP_VIEWS.FOCUS ? focused?.id ?? null : place.resourceId)
    }
  }

  function sync() {
    router.post(resourceMapSyncPath(), {}, { preserveScroll: true, preserveState: true })
  }

  function openAddLink() {
    setAdding(true)
  }

  if (resources.length === 0) {
    return (
      <AuthenticatedLayout title="Map">
        <Head title="Map" />
        <EmptyMap syncing={connections.length > 0} canSync={canSync} readsIn={readsIn} onSync={sync} />
      </AuthenticatedLayout>
    )
  }

  return (
    <AuthenticatedLayout title="Map">
      <Head title="Map" />
      <div className="flex flex-col">
        <header className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-border px-4 py-3 lg:px-6">
          <SyncedLine resources={resources} connections={connections} />
          {readsIn && <ReachNote readsIn={readsIn} />}
          <div className="grow" />
          {canSync && (
            <Button type="button" variant="outline" size="sm" onClick={sync}>
              <IconRefresh className="size-4" />
              Sync now
            </Button>
          )}
        </header>

        <div className="flex flex-wrap items-center gap-2 border-b border-border px-4 py-2.5 lg:px-6">
          <Filters resources={resources} filters={filters} onChange={setFilters} />
          <div className="grow" />
          <ToggleGroup type="single" variant="outline" size="sm" value={place.view} onValueChange={switchView} aria-label="View">
            {Object.values(MAP_VIEWS).map((view) => (
              <ToggleGroupItem key={view} value={view} className="px-3.5">
                {VIEW_LABELS[view]}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>

        {place.view === MAP_VIEWS.MAP && (
          <div className="grid lg:grid-cols-[minmax(0,1fr)_22rem]">
            <div className={CANVAS_HEIGHT}>
              <MapCanvas resources={shown} links={shownLinks} onPick={focusOn} />
            </div>
            <AttentionPanel resources={resources} links={links} changes={changes} connections={connections} canCurate={canCurate} onPick={focusOn} />
          </div>
        )}

        {place.view === MAP_VIEWS.FOCUS && focused && (
          <FocusView
            focused={focused}
            resources={resources}
            links={links}
            depth={depth}
            direction={direction}
            onDepth={setDepth}
            onDirection={setDirection}
            onPick={focusOn}
          >
            <ResourcePanel
              resource={focused}
              resources={resources}
              links={links}
              changes={changes}
              catalogEntries={catalogEntries}
              canCurate={canCurate}
              onAddLink={openAddLink}
              onPick={focusOn}
            />
          </FocusView>
        )}

        {place.view === MAP_VIEWS.TABLE && <ResourceTable resources={shown} links={shownLinks} onPick={focusOn} />}
      </div>
      <AddLinkDialog key={`${focused?.id ?? "none"}:${adding}`} open={adding} onOpenChange={setAdding} resources={resources} fromId={focused?.id ?? null} />
    </AuthenticatedLayout>
  )
}

function SyncedLine({ resources, connections }: Pick<MapPageProps, "resources" | "connections">) {
  const swept = connections.map((connection) => connection.sweptAt).filter((sweptAt): sweptAt is string => Boolean(sweptAt)).sort()
  const latest = swept[swept.length - 1]
  const accounts = new Set(resources.map((resource) => `${resource.provider}:${resource.account}`)).size
  if (!latest) {
    return null
  }

  return (
    <span className="flex items-center gap-2 text-sm text-muted-foreground">
      <span className="size-1.5 rounded-full bg-success" />
      Synced {timeAgo(latest)} from {accounts} {accounts === 1 ? "account" : "accounts"}
    </span>
  )
}

interface FiltersProps {
  resources: ResourceMapResource[]
  filters: MapFilters
  onChange: (filters: MapFilters) => void
}

function Filters({ resources, filters, onChange }: FiltersProps) {
  const environments = unique(resources.map((resource) => resource.environment))
  const providers = unique(resources.map((resource) => resource.provider))
  const providerNames = new Map(resources.map((resource) => [ resource.provider, resource.providerName ]))
  const kinds = RESOURCE_MAP_KINDS.filter((kind) => resources.some((resource) => resource.kind === kind))

  function search(event: React.ChangeEvent<HTMLInputElement>) {
    onChange({ ...filters, query: event.target.value })
  }

  function environment(value: string) {
    onChange({ ...filters, environment: value === ALL ? null : value })
  }

  function provider(value: string) {
    onChange({ ...filters, provider: value === ALL ? null : value })
  }

  function kind(value: string) {
    onChange({ ...filters, kind: kinds.find((each) => each === value) ?? null })
  }

  return (
    <>
      <div className="relative w-full sm:w-72">
        <IconSearch className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <label htmlFor="map-search" className="sr-only">Search resources</label>
        <Input id="map-search" type="search" placeholder="Search resources, repositories, domains" value={filters.query} onChange={search} className="h-8 pl-8" />
      </div>
      {environments.length > 0 && (
        <FilterSelect label="Environment" value={filters.environment} onChange={environment} options={environments.map((each) => [ each, each ])} />
      )}
      {providers.length > 1 && (
        <FilterSelect label="Provider" value={filters.provider} onChange={provider} options={providers.map((each) => [ each, providerNames.get(each) ?? each ])} />
      )}
      {kinds.length > 1 && <FilterSelect label="Type" value={filters.kind} onChange={kind} options={kinds.map((each) => [ each, KIND_LABELS[each] ])} />}
    </>
  )
}

interface FilterSelectProps {
  label: string
  value: string | null
  onChange: (value: string) => void
  options: [string, string][]
}

function FilterSelect({ label, value, onChange, options }: FilterSelectProps) {
  return (
    <Select value={value ?? ALL} onValueChange={onChange}>
      <SelectTrigger size="sm" className="h-8 min-w-32" aria-label={label}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL}>{`${label}: all`}</SelectItem>
        {options.map(([ optionValue, optionLabel ]) => (
          <SelectItem key={optionValue} value={optionValue}>
            {optionLabel}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

interface FocusViewProps {
  focused: ResourceMapResource
  resources: ResourceMapResource[]
  links: MapPageProps["links"]
  depth: Depth
  direction: Direction
  onDepth: (depth: Depth) => void
  onDirection: (direction: Direction) => void
  onPick: (resourceId: string) => void
  children: React.ReactNode
}

// One resource and everything within the chosen number of links, which is what a failure of it would reach.
function FocusView({ focused, resources, links, depth, direction, onDepth, onDirection, onPick, children }: FocusViewProps) {
  const reached = neighborhood(focused.id, links, depth, direction)
  const near = resources.filter((resource) => reached.has(resource.id))
  const options = resources.map((resource) => ({ value: resource.id, label: `${resource.name} · ${resource.providerName}` }))

  function pick(value: string | null) {
    if (value) {
      onPick(value)
    }
  }

  function chooseDepth(value: string) {
    const chosen = DEPTHS.find((each) => String(each) === value)
    if (chosen) {
      onDepth(chosen)
    }
  }

  function chooseDirection(value: string) {
    const chosen = Object.values(DIRECTIONS).find((each) => each === value)
    if (chosen) {
      onDirection(chosen)
    }
  }

  return (
    <div className="grid lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="flex flex-col">
        <div className="flex flex-wrap items-center gap-2 border-b border-border px-4 py-2.5 lg:px-6">
          <div className="w-64">
            <SearchableSelect value={focused.id} onValueChange={pick} options={options} placeholder="Pick a resource" searchPlaceholder="Search resources" emptyText="Nothing on the map matches" />
          </div>
          <ToggleGroup type="single" variant="outline" size="sm" value={String(depth)} onValueChange={chooseDepth} aria-label="How far out">
            {DEPTHS.map((each) => (
              <ToggleGroupItem key={each} value={String(each)} className="px-3">
                {each} {each === 1 ? "link" : "links"} out
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
          <ToggleGroup type="single" variant="outline" size="sm" value={direction} onValueChange={chooseDirection} aria-label="Which way">
            {Object.values(DIRECTIONS).map((each) => (
              <ToggleGroupItem key={each} value={each} className="px-3">
                {DIRECTION_LABELS[each]}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>
        <div className={CANVAS_HEIGHT}>
          <MapCanvas resources={near} links={linksAmong(links, reached)} focusedId={focused.id} onPick={onPick} />
        </div>
      </div>
      {children}
    </div>
  )
}

// Said once someone reads the map in some environments only, so a resource they do not see reads as outside their reach.
function ReachNote({ readsIn }: { readsIn: string[] }) {
  return (
    <span className="text-sm text-muted-foreground">
      Showing what runs in {listed(readsIn)}. An admin decides which environments you see.
    </span>
  )
}

interface EmptyMapProps {
  syncing: boolean
  canSync: boolean
  readsIn: string[] | null
  onSync: () => void
}

function EmptyMap({ syncing, canSync, readsIn, onSync }: EmptyMapProps) {
  if (readsIn) {
    return (
      <EmptyState
        title="Nothing you can see is on the map yet"
        text={`Nothing on the map runs in ${listed(readsIn)} yet. An admin decides which environments you see.`}
      />
    )
  }

  const title = syncing ? "The map is filling in" : "Nothing is on the map yet"
  if (syncing) {
    return (
      <EmptyState title={title} text="Firefight is reading what your connections reach. It takes a minute, and the map fills in as each one finishes.">
        {canSync && (
          <Button type="button" variant="outline" size="sm" onClick={onSync}>
            <IconRefresh className="size-4" />
            Sync now
          </Button>
        )}
      </EmptyState>
    )
  }

  if (!canSync) {
    return <EmptyState title={title} text="The map shows what runs where, read off your connections. Once an admin connects a provider, Firefight reads what runs there." />
  }

  return (
    <EmptyState
      title={title}
      text="The map shows what runs where, read off your connections. Connect Northflank or PlanetScale and Firefight reads what runs there, and how it depends on each other."
    >
      <Button asChild size="sm">
        <Link href={integrationsPath()}>Connect a provider</Link>
      </Button>
    </EmptyState>
  )
}

function EmptyState({ title, text, children }: { title: string; text: string; children?: React.ReactNode }) {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 px-4 py-24 text-center">
      <span className="flex size-12 items-center justify-center rounded-xl bg-muted">
        <IconTopologyStar3 className="size-6 text-muted-foreground" />
      </span>
      <h1 className="text-lg font-semibold">{title}</h1>
      <p className="text-sm text-muted-foreground">{text}</p>
      {children}
    </div>
  )
}

function listed(names: string[]): string {
  if (names.length <= 1) {
    return names[0] ?? ""
  }
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
}

function unique(values: (string | undefined)[]): string[] {
  return [ ...new Set(values.filter((value): value is string => Boolean(value))) ].sort()
}
