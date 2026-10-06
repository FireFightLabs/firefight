import { Link, router } from "@inertiajs/react"
import { IconPlus, IconSearch } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { formatDate } from "@/lib/formatters"
import { confirmMemoryPath, destroyMemoryPath, incidentPath } from "@/lib/routes"
import { AddMemoryDialog } from "@/pages/memory/components/add-memory-dialog"
import { DecideMemoryDialog, type Decision, DECISIONS } from "@/pages/memory/components/decide-memory-dialog"
import { FILTER_LABELS, inFilter, STATE_LABELS, STATE_TONES, vouch } from "@/pages/memory/lib/labels"
import { RowActions } from "@/pages/settings/components/row-actions"
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
}

export function MemoriesTab({ memories, subjects, canCurate }: MemoriesTabProps) {
  const [ filter, setFilter ] = useState<MemoryFilter>(MEMORY_FILTERS.IN_USE)
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

  function search(event: React.ChangeEvent<HTMLInputElement>) {
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
      router.delete(destroyMemoryPath(deleting.id), { preserveScroll: true, onFinish: cancelDelete })
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
                <MemoryRow key={memory.id} memory={memory} canCurate={canCurate} onDecide={setDeciding} onDelete={setDeleting} />
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

interface MemoryRowProps {
  memory: ChatMemory
  canCurate: boolean
  onDecide: (choice: { memory: ChatMemory; decision: Decision }) => void
  onDelete: (memory: ChatMemory) => void
}

function MemoryRow({ memory, canCurate, onDecide, onDelete }: MemoryRowProps) {
  const decidable = !memory.rejectBlockedReason
  const confirmable = !memory.confirmBlockedReason

  function confirm() {
    router.post(confirmMemoryPath(memory.id), {}, { preserveScroll: true })
  }

  function correct() {
    onDecide({ memory, decision: DECISIONS.CORRECT })
  }

  function reject() {
    onDecide({ memory, decision: DECISIONS.REJECT })
  }

  function remove() {
    onDelete(memory)
  }

  return (
    <TableRow className="align-top">
      <TableCell className="max-w-xl min-w-64 pl-6 whitespace-normal">
        <div className="flex flex-col gap-1.5 py-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${STATE_TONES[memory.state]}`}>{STATE_LABELS[memory.state]}</span>
            {memory.about && (
              <span className="text-xs text-muted-foreground">
                About {memory.about}
                {memory.aboutRemoved && ", which is no longer on the map"}
              </span>
            )}
          </div>
          <p className="text-sm leading-relaxed">{memory.text}</p>
          {memory.reason && <p className="text-xs text-muted-foreground">{memory.reason}</p>}
        </div>
      </TableCell>
      <TableCell className="min-w-48 whitespace-normal">
        <div className="flex flex-col gap-0.5 py-1 text-sm">
          {memory.sourceIncidentId ? (
            <Link href={incidentPath(memory.sourceIncidentId)} className="hover:underline">
              {memory.sourceLabel}
            </Link>
          ) : (
            <span>{memory.sourceLabel}</span>
          )}
          <span className="text-xs text-muted-foreground">
            {vouch(memory)}, {formatDate(memory.confirmedAt ?? memory.createdAt)}
          </span>
        </div>
      </TableCell>
      <TableCell className="text-sm whitespace-nowrap text-muted-foreground tabular-nums">
        <div className="py-1">
          {memory.useCount === 0 ? "Not yet" : `${memory.useCount} ${memory.useCount === 1 ? "time" : "times"}`}
          {memory.lastUsedAt && <div className="text-xs">Last {formatDate(memory.lastUsedAt)}</div>}
        </div>
      </TableCell>
      {canCurate && (
        <TableCell className="pr-6 text-right">
          <div className="flex items-center justify-end gap-1.5 py-0.5">
            {decidable && (
              <>
                {confirmable && (
                  <Button type="button" size="sm" variant="outline" onClick={confirm}>
                    Confirm
                  </Button>
                )}
                <Button type="button" size="sm" variant="outline" onClick={correct}>
                  Correct
                </Button>
                <Button type="button" size="sm" variant="ghost" className="text-muted-foreground" onClick={reject}>
                  Not right
                </Button>
              </>
            )}
            <RowActions onDelete={remove} />
          </div>
        </TableCell>
      )}
    </TableRow>
  )
}

function matches(memory: ChatMemory, needle: string): boolean {
  if (!needle) {
    return true
  }
  return [ memory.text, memory.about, memory.sourceLabel ].some((value) => value?.toLowerCase().includes(needle))
}
