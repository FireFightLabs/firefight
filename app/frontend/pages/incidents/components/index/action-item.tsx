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
  open: "text-muted-foreground",
  in_progress: "text-amber-400",
  done: "text-primary",
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
    <div className="py-3 border-b border-border/60 last:border-b-0">
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 shrink-0 ${statusColor}`}>
          <StatusIcon className="block size-[15px]" strokeWidth={1.75} />
        </div>
        <p className={`text-[13px] leading-[1.5] ${isDone ? "line-through text-muted-foreground/60" : "text-foreground"}`}>
          {action.description}
        </p>
      </div>
      <div className="mt-1 flex items-center gap-1.5 pl-[27px] text-xs text-muted-foreground/60">
        {action.assignee ? (
          <span className="inline-flex items-center gap-1.5">
            <IconUser className="size-3" />
            {action.assignee}
          </span>
        ) : (
          <span className="italic text-muted-foreground/40">Unassigned</span>
        )}
        <span className="text-muted-foreground/50">·</span>
        <span className={statusColor}>{statusLabels[action.status]}</span>
      </div>
    </div>
  )
}
