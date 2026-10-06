import type { SharedProps } from "@/types"
import { RESOURCE_MAP_PAGE_QUERY, RESOURCE_MAP_VIEWS, type ResourceMapKind } from "@/lib/generated/constants"
import type {
  ResourceMapChange,
  ResourceMapConnection,
  ResourceMapEntry,
  ResourceMapLink,
  ResourceMapResource,
} from "@/types/serializers"

export interface MapPageProps extends SharedProps {
  [key: string]: unknown
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  connections: ResourceMapConnection[]
  changes: ResourceMapChange[]
  catalogEntries: ResourceMapEntry[]
  // The environments this person reads the map in, by name, or null when they read every one.
  readsIn: string[] | null
}

export const MAP_VIEWS = RESOURCE_MAP_VIEWS
export type MapView = (typeof MAP_VIEWS)[keyof typeof MAP_VIEWS]

// The view and the focused resource live in the address, so a link from search, a chat or a teammate opens the same place.
export const MAP_QUERY = RESOURCE_MAP_PAGE_QUERY

// A link reads "from depends on to", so what a resource needs lies along its links out, and what needs it along its links in.
export const DIRECTIONS = { BOTH: "both", NEEDS: "needs", NEEDED_BY: "needed_by" } as const
export type Direction = (typeof DIRECTIONS)[keyof typeof DIRECTIONS]

export const DEPTHS = [ 1, 2, 3 ] as const
export type Depth = (typeof DEPTHS)[number]

export interface MapFilters {
  query: string
  environment: string | null
  provider: string | null
  kind: ResourceMapKind | null
}
