import {
  IconCircleCheck,
  IconClock,
  IconLoader,
  IconUser,
} from "@tabler/icons-react"

import type { IncidentAction } from "@/pages/incidents/types"

const statusIcons: Record<string, typeof IconClock> = {
  open: IconClock,
  in_progress: IconLoader,
  done: IconCircleCheck,
}

const statusStyles: Record<string, string> = {
  open: "text-muted-foreground/50",
  in_progress: "text-amber-400",
  done: "text-emerald-400",
}

const statusLabels: Record<string, string> = {
  open: "Open",
  in_progress: "In progress",
  done: "Done",
}

export function ActionItem({ action }: { action: IncidentAction }) {
  const StatusIcon = statusIcons[action.status]
  const statusColor = statusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div className="group flex items-start gap-3 py-2 first:pt-0 last:pb-0 border-b border-border/60 last:border-b-0">
      <div className={`mt-0.5 shrink-0 ${statusColor}`}>
        <StatusIcon className="size-[15px]" strokeWidth={1.75} />
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-[13px] leading-[1.5] ${isDone ? "line-through text-muted-foreground/50" : "text-foreground"}`}>
          {action.description}
        </p>
        <div className="mt-0.5 flex items-center gap-2 text-[11px] text-muted-foreground/60">
          {action.assignee ? (
            <span className="inline-flex items-center gap-1">
              <IconUser className="size-3" />
              {action.assignee}
            </span>
          ) : (
            <span className="italic text-muted-foreground/40">Unassigned</span>
          )}
          <span className="size-1 rounded-full bg-muted-foreground/30" />
          <span className={statusColor}>{statusLabels[action.status]}</span>
        </div>
      </div>
    </div>
  )
}
