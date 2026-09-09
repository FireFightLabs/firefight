import { CHANGE_KINDS } from "@/lib/generated/constants"
import type { TimelineChange } from "@/pages/incidents/types"
import { TimelineTextChange } from "@/pages/incidents/components/index/timeline-text-change"
import { TimelineValueChange } from "@/pages/incidents/components/index/timeline-value-change"

// One row per changed field. The label column is fixed so values line up
// down the card, and a hairline separates rows instead of a chip per label.
export function TimelineChangeList({ changes }: { changes: TimelineChange[] }) {
  return (
    <div className="-my-1 flex flex-col">
      {changes.map((change) => (
        <div
          key={change.field}
          className="grid grid-cols-[96px_minmax(0,1fr)] items-baseline gap-3.5 border-t border-border py-2 first:border-t-0"
        >
          <span className="text-xs font-medium text-muted-foreground">{change.label}</span>
          {change.kind === CHANGE_KINDS.TEXT ? (
            <TimelineTextChange change={change} />
          ) : (
            <TimelineValueChange change={change} />
          )}
        </div>
      ))}
    </div>
  )
}
