import type { IncidentAction } from "@/pages/incidents/types"
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
}: {
  title: string
  items: IncidentAction[]
  canAdd: boolean
  incidentId: string
  actionType: "action" | "followup"
  disabledTooltip: string
}) {
  const doneCount = items.filter((a) => a.status === "done").length
  const isEmpty = items.length === 0

  return (
    <section className={`rounded-xl border border-border bg-card overflow-hidden transition-opacity ${canAdd ? "" : "opacity-50"}`}>
      <header className="flex items-center justify-between px-5 pt-4 pb-2.5">
        <h3 className="text-[12px] font-semibold uppercase tracking-[0.10em] text-foreground">
          {title}
        </h3>
        <AddActionDialog disabled={!canAdd} incidentId={incidentId} actionType={actionType} disabledTooltip={disabledTooltip} />
      </header>
      <div className="px-5 pb-2">
        <ProgressRail done={doneCount} total={items.length} />
      </div>
      {!isEmpty && (
        <div className="px-5 pt-2 pb-5">
          {items.map((action) => (
            <ActionItem key={action.id} action={action} />
          ))}
        </div>
      )}
      {isEmpty && (
        <div className="px-5 pb-5 text-[12px] text-muted-foreground/70">
          None yet.
        </div>
      )}
    </section>
  )
}
