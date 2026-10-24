import { type Icon, IconCheck, IconCircleDashed, IconExternalLink, IconLoader2, IconMinus, IconPlayerSkipForward, IconTool, IconX } from "@tabler/icons-react"

import { WATCH_STEP_STATUSES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import { clockLabel } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunStep } from "@/types/serializers"

type Watched = NonNullable<WorkflowRunStep["watch"]>["steps"][number]

const MARKS: Record<Watched["status"], { icon: Icon; className: string }> = {
  [WATCH_STEP_STATUSES.WAITING]: { icon: IconCircleDashed, className: "text-fg-muted" },
  [WATCH_STEP_STATUSES.RUNNING]: { icon: IconLoader2, className: "text-warning motion-safe:animate-spin" },
  [WATCH_STEP_STATUSES.REPAIRING]: { icon: IconTool, className: "text-warning" },
  [WATCH_STEP_STATUSES.SUCCEEDED]: { icon: IconCheck, className: "text-success" },
  [WATCH_STEP_STATUSES.FAILED]: { icon: IconX, className: "text-error" },
  [WATCH_STEP_STATUSES.UNFOLLOWABLE]: { icon: IconMinus, className: "text-fg-muted" },
  [WATCH_STEP_STATUSES.SKIPPED]: { icon: IconPlayerSkipForward, className: "text-fg-muted" },
}

// One thing a watch follows: where it stands in a few words, the page of its run when the provider gave one, and what it
// saw last with when.
export function WatchedThing({ watched }: { watched: Watched }) {
  const Mark = MARKS[watched.status].icon

  return (
    <li className="space-y-1 text-xs">
      <div className="flex items-start gap-1.5">
        <Mark className={cn("mt-0.5 size-3.5 shrink-0", MARKS[watched.status].className)} />
        <p className="min-w-0 [overflow-wrap:anywhere]">
          <span className="font-medium text-fg-primary">{watched.label}</span>
          {watched.line && <span className="text-fg-secondary">. {watched.line}</span>}
          {watched.url && (
            <a href={watched.url} target="_blank" rel="noopener noreferrer" className="ml-1.5 inline-flex items-center gap-1 whitespace-nowrap text-link underline underline-offset-2">
              <IconExternalLink className="size-3" />
              Open the run
            </a>
          )}
        </p>
      </div>
      {watched.lastSeen && (
        <div className="ml-5 space-y-0.5">
          <p className="text-[11px] text-fg-muted">What it saw last{watched.readAt ? `, at ${clockLabel(watched.readAt)}` : ""}</p>
          <pre className="max-h-32 overflow-auto rounded-sm border border-border bg-surface-code px-2 py-1.5 font-mono text-[11px] leading-relaxed whitespace-pre-wrap text-fg-primary [overflow-wrap:anywhere]">
            {watched.lastSeen}
          </pre>
        </div>
      )}
    </li>
  )
}
