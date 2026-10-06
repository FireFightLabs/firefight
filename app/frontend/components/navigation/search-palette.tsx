import { router } from "@inertiajs/react"
import { IconBook2, IconBrain, type Icon } from "@tabler/icons-react"
import { useState } from "react"

import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useRemoteSearch } from "@/hooks/use-remote-search"
import { MAP_SEARCH_TYPE } from "@/lib/generated/constants"
import { mapSearchPath } from "@/lib/routes"
import { KIND_ICONS } from "@/pages/map/lib/icons"
import { KIND_LABELS } from "@/pages/map/lib/labels"
import type { MapSearchResult } from "@/types/serializers"

interface SearchPaletteProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

function searchPath(query: string) {
  return mapSearchPath({ q: query })
}

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

// One search across the map, the catalog and confirmed memories, ranked together by the server.
export function SearchPalette({ open, onOpenChange }: SearchPaletteProps) {
  const [ query, setQuery ] = useState("")
  const { results, search } = useRemoteSearch<MapSearchResult>(searchPath)
  const shown = query.trim() ? results ?? [] : []

  // The server ranks, so the first result is selected here for Enter to open it.
  const shownKeys = shown.map((result) => `${result.type}:${result.id}`).join(" ")
  const [ selected, setSelected ] = useState("")
  const [ selectedFor, setSelectedFor ] = useState(shownKeys)
  if (shownKeys !== selectedFor) {
    setSelectedFor(shownKeys)
    setSelected(shown[0] ? `${shown[0].type}:${shown[0].id}` : "")
  }

  function changeQuery(next: string) {
    setQuery(next)
    search(next)
  }

  function choose(result: MapSearchResult) {
    onOpenChange(false)
    router.visit(result.href)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader className="sr-only">
        <DialogTitle>Search</DialogTitle>
        <DialogDescription>Find a resource on the map, a catalog entry or a confirmed memory.</DialogDescription>
      </DialogHeader>
      <DialogContent className="overflow-hidden p-0 sm:max-w-2xl" showCloseButton={false}>
        <Command
          shouldFilter={false}
          value={selected}
          onValueChange={setSelected}
          className="**:data-[slot=command-input-wrapper]:h-12 [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground [&_[cmdk-group]]:px-2 [&_[cmdk-item]]:px-2 [&_[cmdk-item]]:py-2.5"
        >
          <CommandInput placeholder="Search the map, catalog and memory" value={query} onValueChange={changeQuery} />
          <CommandList className="max-h-[min(28rem,70dvh)]">
            {query.trim() === "" ? (
              <p className="px-4 py-6 text-sm text-muted-foreground">
                Find a resource, a catalog entry or a confirmed memory by its name, an id or part of one, a tag, the team that owns it, or what a service does.
              </p>
            ) : (
              <>
                {results && <CommandEmpty>Nothing you can see matches that.</CommandEmpty>}
                {shown.length > 0 && (
                  <CommandGroup heading="Best matches first">
                    {shown.map((result) => (
                      <SearchResultItem key={`${result.type}:${result.id}`} result={result} onChoose={choose} />
                    ))}
                  </CommandGroup>
                )}
              </>
            )}
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  )
}

function SearchResultItem({ result, onChoose }: { result: MapSearchResult; onChoose: (result: MapSearchResult) => void }) {
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
