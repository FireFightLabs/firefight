import type { ReactNode } from "react"

import { SearchableSelect } from "@/components/searchable-select"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { MapCanvas } from "@/pages/map/components/map-canvas"
import { linksAmong, neighborhood } from "@/pages/map/lib/graph"
import { CANVAS_HEIGHT } from "@/pages/map/lib/layout"
import { DEPTHS, type Depth, type Direction, DIRECTIONS, type MapPageProps } from "@/pages/map/types"
import type { ResourceMapResource } from "@/types/serializers"

const DIRECTION_LABELS: Record<Direction, string> = { both: "Both ways", needs: "What it needs", needed_by: "What needs it" }

interface FocusViewProps {
  focused: ResourceMapResource
  resources: ResourceMapResource[]
  links: MapPageProps["links"]
  depth: Depth
  direction: Direction
  onDepth: (depth: Depth) => void
  onDirection: (direction: Direction) => void
  onPick: (resourceId: string) => void
  children: ReactNode
}

// One resource and everything within the chosen number of links, which is what a failure of it would reach.
export function FocusView({ focused, resources, links, depth, direction, onDepth, onDirection, onPick, children }: FocusViewProps) {
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
