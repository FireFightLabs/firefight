import { IconArrowRight } from "@tabler/icons-react"
import { CHANGE_KINDS } from "@/lib/generated/constants"
import { formatDateTime } from "@/lib/formatters"
import type { TimelineChange } from "@/pages/incidents/types"

// A short value reads inline: the old value struck, an arrow, the new value.
// A value set for the first time drops the strike and the arrow, and a value
// taken away ends in a word rather than an arrow pointing at nothing.
export function TimelineValueChange({ change }: { change: TimelineChange }) {
  const isTime = change.kind === CHANGE_KINDS.TIME
  const before = isTime && change.before ? formatDateTime(change.before) : change.before
  const after = isTime && change.after ? formatDateTime(change.after) : change.after
  const valueClass = isTime ? "font-mono text-[13px] tabular-nums" : ""

  return (
    <span className="flex flex-wrap items-baseline gap-x-2 gap-y-1 text-sm leading-normal">
      {before && (
        <>
          <span className={`text-muted-foreground/70 line-through decoration-muted-foreground/40 ${valueClass}`}>
            {before}
          </span>
          <IconArrowRight className="size-3 self-center text-muted-foreground/60" />
        </>
      )}
      {after ? (
        <span className={`font-medium text-foreground ${valueClass}`}>{after}</span>
      ) : (
        <span className="italic text-muted-foreground/70">Cleared</span>
      )}
    </span>
  )
}
