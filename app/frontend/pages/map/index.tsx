import { Head, router, usePage } from "@inertiajs/react"
import { IconRefresh } from "@tabler/icons-react"
import { useCallback, useMemo, useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { useCan } from "@/lib/permissions"
import { replaceQuery } from "@/lib/query"
import { resourceMapSyncPath } from "@/lib/routes"
import { AddLinkDialog } from "@/pages/map/components/add-link-dialog"
import { AttentionPanel } from "@/pages/map/components/attention-panel"
import { EmptyMap } from "@/pages/map/components/empty-map"
import { FiltersBar } from "@/pages/map/components/filters-bar"
import { FocusView } from "@/pages/map/components/focus-view"
import { MapCanvas } from "@/pages/map/components/map-canvas"
import { ReachNote } from "@/pages/map/components/reach-note"
import { ResourcePanel } from "@/pages/map/components/resource-panel"
import { ResourceTable } from "@/pages/map/components/resource-table"
import { SyncedLine } from "@/pages/map/components/synced-line"
import { linksAmong, matchesFilters } from "@/pages/map/lib/graph"
import { CANVAS_HEIGHT } from "@/pages/map/lib/layout"
import { MAP_VISIT } from "@/pages/map/lib/visit"
import {
  type Depth,
  type Direction,
  DIRECTIONS,
  MAP_QUERY,
  MAP_VIEWS,
  type MapFilters,
  type MapPageProps,
  type MapView,
} from "@/pages/map/types"

const DEFAULT_DEPTH: Depth = 2

const VIEW_LABELS: Record<MapView, string> = { map: "Map", focus: "Focus", table: "Table" }

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
    replaceQuery({ [MAP_QUERY.VIEW]: view, [MAP_QUERY.RESOURCE]: resourceId })
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
    router.post(resourceMapSyncPath(), {}, MAP_VISIT)
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
          <FiltersBar resources={resources} filters={filters} onChange={setFilters} />
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
