import type { IncidentAction } from "@/pages/incidents/types"
import type { InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { ActionPanel } from "@/pages/incidents/components/index/action-panel"

export function IncidentActionsSidebar({
  actions,
  actionBlockedReason,
  followupBlockedReason,
  incidentId,
  candidates,
  canEdit,
}: {
  actions: IncidentAction[]
  actionBlockedReason?: string
  followupBlockedReason?: string
  incidentId: string
  candidates: InlineChoice[]
  canEdit: boolean
}) {
  const actionItems = actions.filter((item) => item.actionType === "action")
  const followups = actions.filter((action) => action.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" items={actionItems} blockedReason={actionBlockedReason} incidentId={incidentId} actionType="action" candidates={candidates} canEdit={canEdit} />
      <ActionPanel title="Follow-ups" items={followups} blockedReason={followupBlockedReason} incidentId={incidentId} actionType="followup" candidates={candidates} canEdit={canEdit} />
    </div>
  )
}
