import { usePage } from "@inertiajs/react"
import { useMemo } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import type { WorkflowPageProps } from "@/pages/halon/lib/workflow/types"
import type { RunbookWatchRead } from "@/types/serializers"

interface CanvasChoices {
  // Things on the map a step's settings pick from, by name, grouped by kind.
  places: SearchableSelectOption[]
  // What a Watch step can read of something on the map, or null while it loads.
  watchReads: RunbookWatchRead[] | null
}

// What a step's settings pick from that the canvas loads after the page, the same lists a runbook's editor offers.
export function useCanvasChoices(): CanvasChoices {
  const { places, watchReads } = usePage<WorkflowPageProps>().props
  return useMemo(() => ({
    places: (places ?? []).map((place) => ({ value: place.name, label: place.name, group: place.kind })),
    watchReads: watchReads ?? null,
  }), [ places, watchReads ])
}
