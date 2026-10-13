import { IconAlertTriangle } from "@tabler/icons-react"

import { formatWhen } from "@/pages/halon/components/workflows/labels"
import type { WorkflowDetail } from "@/types/serializers"

// What a person should know before anything else: a freeze window the workflow's changes would meet, and a start that
// did not happen.
export function WorkflowAlerts({ workflow }: { workflow: WorkflowDetail }) {
  if (!workflow.freezeWarning && !workflow.triggerRefusal) {
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
    </div>
  )
}
