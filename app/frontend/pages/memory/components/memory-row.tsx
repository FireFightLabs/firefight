import { Link, router } from "@inertiajs/react"
import { IconChevronDown } from "@tabler/icons-react"
import { useEffect, useRef, useState } from "react"

import { type Decision, DECISIONS } from "@/components/memory/decide-memory-dialog"
import { Button } from "@/components/ui/button"
import { TableCell, TableRow } from "@/components/ui/table"
import { formatDate, formatDateTime } from "@/lib/formatters"
import { confirmMemoryPath, incidentPath } from "@/lib/routes"
import { STATE_LABELS, STATE_TONES } from "@/lib/memory-labels"
import { checkLine, eventHeadline, vouch } from "@/pages/memory/lib/labels"
import { Blocked } from "@/components/blocked-tooltip"
import { RowActions } from "@/components/row-actions"
import type { ChatMemory } from "@/types/serializers"

interface MemoryRowProps {
  memory: ChatMemory
  focused: boolean
  canCurate: boolean
  onDecide: (choice: { memory: ChatMemory; decision: Decision }) => void
  onDelete: (memory: ChatMemory) => void
}

// Confirm, Correct and Not right stay on every row a person may decide on, whatever Halon's check found, since a person's
// word outranks Halon's. One the memory refuses is inert, with why as its tooltip.
export function MemoryRow({ memory, focused, canCurate, onDecide, onDelete }: MemoryRowProps) {
  const row = useRef<HTMLTableRowElement>(null)
  const [ showHistory, setShowHistory ] = useState(false)
  const confirmReason = memory.confirmBlockedReason ?? undefined
  const rejectReason = memory.rejectBlockedReason ?? undefined
  const checked = checkLine(memory)

  useEffect(() => {
    if (focused) {
      row.current?.scrollIntoView({ block: "center" })
    }
  }, [ focused ])

  function confirm() {
    router.post(confirmMemoryPath(memory.id), {}, { preserveScroll: true, preserveState: true })
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

  function toggleHistory() {
    setShowHistory((shown) => !shown)
  }

  return (
    <TableRow ref={row} data-focused={focused || undefined} className="align-top data-[focused]:bg-brand-tint">
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
          {memory.awaitingDecision && (
            <p className="text-xs font-medium text-warning">Halon could not settle this against production, so it waits on a person. Confirm it, correct it or mark it not right.</p>
          )}
          {checked && <p className="text-xs text-muted-foreground">{checked}</p>}
          {memory.events.length > 0 && (
            <div className="flex flex-col gap-2 pt-0.5">
              <button
                type="button"
                onClick={toggleHistory}
                aria-expanded={showHistory}
                className="flex w-fit items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
              >
                <IconChevronDown className={`size-3.5 transition-transform ${showHistory ? "rotate-180" : ""}`} />
                {showHistory ? "Hide history" : "Show history"}
              </button>
              {showHistory && (
                <ol className="flex flex-col gap-2 border-l border-border pl-4">
                  {memory.events.map((event) => (
                    <li key={event.id} className="flex flex-col gap-0.5">
                      <span className="text-xs text-muted-foreground">
                        {eventHeadline(event)}, {formatDateTime(event.at)}
                      </span>
                      {event.detail && <p className="text-xs whitespace-pre-wrap text-muted-foreground">{event.detail}</p>}
                    </li>
                  ))}
                </ol>
              )}
            </div>
          )}
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
          <span className="text-xs text-muted-foreground">{vouch(memory)}</span>
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
            <Blocked reason={confirmReason}>
              <Button type="button" size="sm" variant="outline" disabled={Boolean(confirmReason)} onClick={confirm}>
                Confirm
              </Button>
            </Blocked>
            <Blocked reason={rejectReason}>
              <Button type="button" size="sm" variant="outline" disabled={Boolean(rejectReason)} onClick={correct}>
                Correct
              </Button>
            </Blocked>
            <Blocked reason={rejectReason}>
              <Button type="button" size="sm" variant="ghost" className="text-muted-foreground" disabled={Boolean(rejectReason)} onClick={reject}>
                Not right
              </Button>
            </Blocked>
            <RowActions onDelete={remove} />
          </div>
        </TableCell>
      )}
    </TableRow>
  )
}
