import { Link, router } from "@inertiajs/react"
import { useEffect, useRef } from "react"

import { type Decision, DECISIONS } from "@/components/memory/decide-memory-dialog"
import { Button } from "@/components/ui/button"
import { TableCell, TableRow } from "@/components/ui/table"
import { formatDate } from "@/lib/formatters"
import { confirmMemoryPath, incidentPath } from "@/lib/routes"
import { STATE_LABELS, STATE_TONES } from "@/lib/memory-labels"
import { vouch } from "@/pages/memory/lib/labels"
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

// Confirm, Correct and Not right stay on every row a person may decide on. One the memory refuses is inert, with why
// as its tooltip.
export function MemoryRow({ memory, focused, canCurate, onDecide, onDelete }: MemoryRowProps) {
  const row = useRef<HTMLTableRowElement>(null)
  const confirmReason = memory.confirmBlockedReason ?? undefined
  const rejectReason = memory.rejectBlockedReason ?? undefined

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
