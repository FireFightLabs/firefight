import type { IncidentAction } from "@/pages/incidents/types"
import { ActionPanel } from "@/pages/incidents/components/index/action-panel"

export function IncidentActionsSidebar({
  actions,
  canAddAction,
  canAddFollowup,
  incidentId,
}: {
  actions: IncidentAction[]
  canAddAction: boolean
  canAddFollowup: boolean
  incidentId: string
}) {
  const actionItems = actions.filter((item) => item.actionType === "action")
  const followups = actions.filter((action) => action.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" items={actionItems} canAdd={canAddAction} incidentId={incidentId} actionType="action" disabledTooltip="Incident is closed" />
      <ActionPanel title="Follow-ups" items={followups} canAdd={canAddFollowup} incidentId={incidentId} actionType="followup" disabledTooltip="Available once incident is resolved" />
    </div>
  )
}
