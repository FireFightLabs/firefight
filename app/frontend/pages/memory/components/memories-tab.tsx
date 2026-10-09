import { router } from "@inertiajs/react"
import { IconPlus, IconSearch } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { destroyMemoryPath } from "@/lib/routes"
import { AddMemoryDialog } from "@/pages/memory/components/add-memory-dialog"
import { DecideMemoryDialog, type Decision, DECISIONS } from "@/components/memory/decide-memory-dialog"
import { MemoryRow } from "@/pages/memory/components/memory-row"
import { FILTER_LABELS, inFilter } from "@/pages/memory/lib/labels"
import { MEMORY_FILTERS, type MemoryFilter, type SubjectOption } from "@/pages/memory/types"
import type { ChatMemory } from "@/types/serializers"

const EMPTY: Record<MemoryFilter, string> = {
  in_use: "Nothing remembered yet. Halon learns from each incident as it ends, and anything you add here is used from then on.",
  unconfirmed: "Nothing unconfirmed. A person or a postmortem has confirmed every memory Halon uses.",
  outdated: "Nothing looks outdated. A memory lands here when what it is about is renamed, archived in the catalog or gone from the map.",
  disputed: "Nothing disputed. Halon moves a memory here when a live result or a postmortem contradicts it, and stops using it until you decide.",
  expired: "Nothing expired. When an admin sets how long unconfirmed memories last under Settings, Workspace, one nobody confirms in time lands here and Halon stops using it.",
  rejected: "Nothing rejected.",
}

interface MemoriesTabProps {
  memories: ChatMemory[]
  subjects: SubjectOption[]
  canCurate: boolean
  // A memory a link points at, such as a search result, shown under the filter that holds it and marked.
  focusedId: string | null
}

function filterHolding(memory: ChatMemory | undefined): MemoryFilter {
  return (memory && Object.values(MEMORY_FILTERS).find((each) => inFilter(memory, each))) ?? MEMORY_FILTERS.IN_USE
}

export function MemoriesTab({ memories, subjects, canCurate, focusedId }: MemoriesTabProps) {
  const [ filter, setFilter ] = useState<MemoryFilter>(() => filterHolding(memories.find((memory) => memory.id === focusedId)))
  const [ query, setQuery ] = useState("")
  const [ adding, setAdding ] = useState(false)
  const [ deciding, setDeciding ] = useState<{ memory: ChatMemory; decision: Decision } | null>(null)
  const [ deleting, setDeleting ] = useState<ChatMemory | null>(null)
  const needle = query.trim().toLowerCase()
  const shown = memories.filter((memory) => inFilter(memory, filter) && matches(memory, needle))

  function chooseFilter(value: string) {
    const chosen = Object.values(MEMORY_FILTERS).find((each) => each === value)
    if (chosen) {
      setFilter(chosen)
    }
  }

  function search(event: ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  function openAdd() {
    setAdding(true)
  }

  function closeDecision() {
    setDeciding(null)
  }

  function remove() {
    if (deleting) {
      router.delete(destroyMemoryPath(deleting.id), { preserveScroll: true, preserveState: true, onFinish: cancelDelete })
    }
  }

  function cancelDelete() {
    setDeleting(null)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>What Halon remembers</CardTitle>
        <CardDescription className="mt-1">
          Facts Halon learned from incidents or was told. It checks each one against live results, and says so when it relies on one nobody confirmed.
        </CardDescription>
        {canCurate && (
          <CardAction>
            <Button type="button" size="sm" onClick={openAdd}>
              <IconPlus className="size-4" />
              Add memory
            </Button>
          </CardAction>
        )}
      </CardHeader>
      <CardContent className="flex flex-col gap-4 p-0">
        <div className="flex flex-wrap items-center gap-2 px-6">
          <ToggleGroup type="single" variant="outline" size="sm" value={filter} onValueChange={chooseFilter} aria-label="Show" className="flex-wrap">
            {Object.values(MEMORY_FILTERS).map((each) => (
              <ToggleGroupItem key={each} value={each} className="gap-1.5 px-3">
                {FILTER_LABELS[each]}
                <span className="text-xs text-muted-foreground tabular-nums">{memories.filter((memory) => inFilter(memory, each)).length}</span>
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
          <div className="grow" />
          <div className="relative w-full sm:w-64">
            <IconSearch className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
            <label htmlFor="memory-search" className="sr-only">Search memories</label>
            <Input id="memory-search" type="search" placeholder="Search memories" value={query} onChange={search} className="h-8 pl-8" />
          </div>
        </div>
        {shown.length === 0 ? (
          <p className="px-6 pt-4 pb-10 text-center text-sm text-muted-foreground">{needle ? "No memory matches that search." : EMPTY[filter]}</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="pl-6">Memory</TableHead>
                <TableHead>From</TableHead>
                <TableHead>Used</TableHead>
                {canCurate && <TableHead className="pr-6 text-right">Decide</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {shown.map((memory) => (
                <MemoryRow key={memory.id} memory={memory} focused={memory.id === focusedId} canCurate={canCurate} onDecide={setDeciding} onDelete={setDeleting} />
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <AddMemoryDialog key={`add:${adding}`} open={adding} onOpenChange={setAdding} subjects={subjects} />
      <DecideMemoryDialog
        key={deciding ? `${deciding.memory.id}:${deciding.decision}` : "none"}
        memory={deciding?.memory ?? null}
        decision={deciding?.decision ?? DECISIONS.REJECT}
        onClose={closeDecision}
      />
      <ConfirmDeleteDialog
        open={deleting !== null}
        title="Delete this memory?"
        description={`"${deleting?.text ?? ""}" is deleted for good. ${deleting?.deleteConsequence ?? ""}`}
        onConfirm={remove}
        onCancel={cancelDelete}
      />
    </Card>
  )
}

function matches(memory: ChatMemory, needle: string): boolean {
  if (!needle) {
    return true
  }
  return [ memory.text, memory.about, memory.sourceLabel ].some((value) => value?.toLowerCase().includes(needle))
}
