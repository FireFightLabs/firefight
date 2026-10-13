import { IconAlertTriangle } from "@tabler/icons-react"

import { formatTime } from "@/lib/formatters"
import { formatWhen } from "@/pages/halon/components/workflows/labels"
import type { WorkflowDetail } from "@/types/serializers"

const HOUR_MS = 60 * 60 * 1000

// "Oct 14, 14:00 to 15:00", in the viewer's own time zone.
function hourRange(hour: string): string {
  const day = new Date(hour).toLocaleDateString("en-US", { month: "short", day: "numeric" })
  return `${day}, ${formatTime(hour)} to ${formatTime(new Date(new Date(hour).getTime() + HOUR_MS).toISOString())}`
}

// What a person should know before anything else: a freeze window the workflow's changes would meet, a start that did
// not happen, and the runs its trigger would have started past its most runs per hour, by the hour they were skipped in.
export function WorkflowAlerts({ workflow }: { workflow: WorkflowDetail }) {
  if (!workflow.freezeWarning && !workflow.triggerRefusal && !workflow.skippedRunsSentence) {
    return null
  }

  return (
    <div className="space-y-1 border-b border-border px-4 py-2">
      {workflow.freezeWarning && (
        <p className="flex items-start gap-2 text-[13px] text-warning">
          <IconAlertTriangle className="mt-0.5 size-4 shrink-0" />
          {workflow.freezeWarning}
        </p>
      )}
      {workflow.triggerRefusal && (
        <p className="flex items-start gap-2 text-[13px] text-error">
          <IconAlertTriangle className="mt-0.5 size-4 shrink-0" />
          Its last start {workflow.triggerRefusedAt && `on ${formatWhen(workflow.triggerRefusedAt)} `}did not happen. {workflow.triggerRefusal}
        </p>
      )}
      {workflow.skippedRunsSentence && (
        <div className="flex items-start gap-2 text-[13px] text-warning" data-testid="skipped-runs">
          <IconAlertTriangle className="mt-0.5 size-4 shrink-0" />
          <div className="space-y-1">
            <p>{workflow.skippedRunsSentence} Raise its most runs per hour under Settings to let more start.</p>
            <ul className="space-y-0.5 text-xs text-fg-muted">
              {workflow.skippedRuns.map((skipped) => (
                <li key={skipped.hour}>
                  {hourRange(skipped.hour)}: {skipped.count} skipped, the last at {formatTime(skipped.lastAt)}
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  )
}
