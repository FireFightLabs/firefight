import { IconUser } from "@tabler/icons-react"

import type { IncidentAction } from "@/pages/incidents/types"
import { actionAnchorId } from "@/pages/incidents/lib/action-anchor"
import { actionStatusIcons, actionStatusLabels, actionStatusStyles } from "@/pages/incidents/lib/action-status"

export function ActionItem({ action }: { action: IncidentAction }) {
  const StatusIcon = actionStatusIcons[action.status]
  const statusColor = actionStatusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div id={actionAnchorId(action.id)} className="py-3 border-b border-border/60 last:border-b-0 transition-shadow">
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
            {action.assigneeAvatarUrl ? (
              <img
                src={action.assigneeAvatarUrl}
                alt=""
                className="size-3.5 rounded-full object-cover"
              />
            ) : (
              <IconUser className="size-3" />
            )}
            {action.assignee}
          </span>
        ) : (
          <span className="italic text-muted-foreground/40">Unassigned</span>
        )}
        <span className="text-muted-foreground/50">·</span>
        <span className={statusColor}>{actionStatusLabels[action.status]}</span>
      </div>
    </div>
  )
}
