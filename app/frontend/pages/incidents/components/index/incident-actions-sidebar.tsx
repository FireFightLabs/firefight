import type { IncidentAction } from "@/pages/incidents/types"
import type { InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { ActionPanel } from "@/pages/incidents/components/index/action-panel"

export function IncidentActionsSidebar({
  actions,
  canAddAction,
  canAddFollowup,
  incidentId,
  candidates,
  canEdit,
}: {
  actions: IncidentAction[]
  canAddAction: boolean
  canAddFollowup: boolean
  incidentId: string
  candidates: InlineChoice[]
  canEdit: boolean
}) {
  const actionItems = actions.filter((item) => item.actionType === "action")
  const followups = actions.filter((action) => action.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" items={actionItems} canAdd={canAddAction} incidentId={incidentId} actionType="action" disabledTooltip="Incident is closed" candidates={candidates} canEdit={canEdit} />
      <ActionPanel title="Follow-ups" items={followups} canAdd={canAddFollowup} incidentId={incidentId} actionType="followup" disabledTooltip="Available once incident is resolved" candidates={candidates} canEdit={canEdit} />
    </div>
  )
}
