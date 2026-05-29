import { IconCheckbox, IconChecks } from "@tabler/icons-react"

import type { IncidentAction } from "@/pages/incidents/types"
import { ActionPanel } from "@/pages/incidents/components/index/action-panel"

export function IncidentActionsSidebar({
  actions,
  canAdd,
  incidentId,
}: {
  actions: IncidentAction[]
  canAdd: boolean
  incidentId: string
}) {
  const actionItems = actions.filter((a) => a.actionType === "action")
  const followups = actions.filter((a) => a.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" icon={IconCheckbox} items={actionItems} canAdd={canAdd} incidentId={incidentId} actionType="action" />
      <ActionPanel title="Follow-ups" icon={IconChecks} items={followups} canAdd={canAdd} incidentId={incidentId} actionType="followup" />
    </div>
  )
}
