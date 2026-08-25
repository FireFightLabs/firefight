import type { IncidentAction } from "@/pages/incidents/types"
import type { InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { ActionItem } from "@/pages/incidents/components/index/action-item"
import { AddActionDialog } from "@/pages/incidents/components/index/add-action-dialog"
import { ProgressRail } from "@/pages/incidents/components/index/progress-rail"

export function ActionPanel({
  title,
  items,
  canAdd,
  incidentId,
  actionType,
  disabledTooltip,
  candidates,
  canEdit,
}: {
  title: string
  items: IncidentAction[]
  canAdd: boolean
  incidentId: string
  actionType: "action" | "followup"
  disabledTooltip: string
  candidates: InlineChoice[]
  canEdit: boolean
}) {
  const doneCount = items.filter((item) => item.status === "done").length
  const isEmpty = items.length === 0

  if (isEmpty) {
    return (
      <section className={`flex items-center justify-between rounded-xl border border-border bg-card px-4 py-2 transition-opacity ${canAdd ? "" : "opacity-50"}`}>
        <span className="text-[12px] text-muted-foreground">
          {title} · None yet
        </span>
        <AddActionDialog disabled={!canAdd} incidentId={incidentId} actionType={actionType} disabledTooltip={disabledTooltip} />
      </section>
    )
  }

  return (
    <section className={`rounded-xl border border-border bg-card overflow-hidden transition-opacity ${canAdd ? "" : "opacity-50"}`}>
      <header className="flex items-center justify-between px-5 pt-6 pb-2.5">
        <h3 className="text-[12px] font-semibold uppercase tracking-[0.10em] text-foreground">
          {title}
        </h3>
        <AddActionDialog disabled={!canAdd} incidentId={incidentId} actionType={actionType} disabledTooltip={disabledTooltip} />
      </header>
      <div className="px-5 pb-2">
        <ProgressRail done={doneCount} total={items.length} />
      </div>
      <div className="px-5 pt-0 pb-5">
        {items.map((action) => (
          <ActionItem
            key={action.id}
            action={action}
            incidentId={incidentId}
            candidates={candidates}
            canEdit={canEdit}
          />
        ))}
      </div>
    </section>
  )
}
