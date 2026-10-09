import { router } from "@inertiajs/react"
import { useState } from "react"

import { Command, CommandEmpty, CommandGroup, CommandInput, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useRemoteSearch } from "@/hooks/use-remote-search"
import { mapSearchPath } from "@/lib/routes"
import { SearchResultItem } from "@/components/navigation/search-result-item"
import type { MapSearchResult } from "@/types/serializers"

// What the search answers with. refusal says why nothing can be found, such as a person who reads no part of the map.
interface MapSearchResponse {
  results: MapSearchResult[]
  refusal: string | null
}

interface SearchPaletteProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

function searchPath(query: string) {
  return mapSearchPath({ q: query })
}

// One search across the map, the catalog and confirmed memories, ranked together by the server.
export function SearchPalette({ open, onOpenChange }: SearchPaletteProps) {
  const [ query, setQuery ] = useState("")
  const { results: answer, search } = useRemoteSearch<MapSearchResponse>(searchPath)
  const shown = query.trim() ? answer?.results ?? [] : []
  const refusal = query.trim() ? answer?.refusal : null

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
            ) : refusal ? (
              <p className="px-4 py-6 text-sm text-muted-foreground">{refusal}</p>
            ) : (
              <>
                {answer && <CommandEmpty>Nothing you can see matches that.</CommandEmpty>}
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
