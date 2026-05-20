import { IconCheckbox, IconChecks } from "@tabler/icons-react"

import type { IncidentAction } from "@/pages/incidents/types"
import { ActionPanel } from "@/pages/incidents/components/action-panel"

export function IncidentActionsSidebar({ actions }: { actions: IncidentAction[] }) {
  const actionItems = actions.filter((a) => a.actionType === "action")
  const followups = actions.filter((a) => a.actionType === "followup")

  return (
    <div className="flex flex-col gap-3">
      <ActionPanel title="Actions" icon={IconCheckbox} items={actionItems} />
      <ActionPanel title="Follow-ups" icon={IconChecks} items={followups} />
    </div>
  )
}
