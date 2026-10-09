import { IconBook2, IconBrain, type Icon } from "@tabler/icons-react"

import { CommandItem } from "@/components/ui/command"
import { MAP_SEARCH_TYPE } from "@/lib/generated/constants"
import { KIND_ICONS, KIND_LABELS } from "@/lib/resource-map-kinds"
import type { MapSearchResult } from "@/types/serializers"

function iconFor(result: MapSearchResult): Icon {
  if (result.type === MAP_SEARCH_TYPE.RESOURCE && result.kind) {
    return KIND_ICONS[result.kind]
  }
  return result.type === MAP_SEARCH_TYPE.MEMORY ? IconBrain : IconBook2
}

// Where a result lives, in a line: a resource's kind, provider, account and environment, an entry's catalog type, what a memory is about.
function placeOf(result: MapSearchResult): string {
  if (result.type === MAP_SEARCH_TYPE.RESOURCE) {
    return [ result.kind && KIND_LABELS[result.kind], result.providerName, result.account, result.environment ].filter(Boolean).join(" · ")
  }
  if (result.type === MAP_SEARCH_TYPE.CATALOG_ENTRY) {
    return `${result.catalogType ?? "Catalog"} in the catalog`
  }
  return result.about ? `Confirmed memory about ${result.about}` : "Confirmed memory about the whole workspace"
}

export function SearchResultItem({ result, onChoose }: { result: MapSearchResult; onChoose: (result: MapSearchResult) => void }) {
  const ResultIcon = iconFor(result)

  function choose() {
    onChoose(result)
  }

  return (
    <CommandItem value={`${result.type}:${result.id}`} onSelect={choose} className="items-start gap-3">
      <ResultIcon className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-sm font-medium">{result.title}</span>
        <span className="truncate text-xs text-muted-foreground">{placeOf(result)}</span>
        <span className="truncate text-xs text-fg-secondary">{result.why}</span>
      </div>
    </CommandItem>
  )
}
