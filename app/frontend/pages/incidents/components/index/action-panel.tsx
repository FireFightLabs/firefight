import type { Icon as TablerIcon } from "@tabler/icons-react"

import type { IncidentAction } from "@/pages/incidents/types"
import { ActionItem } from "@/pages/incidents/components/index/action-item"
import { AddActionDialog } from "@/pages/incidents/components/index/add-action-dialog"
import { ProgressRail } from "@/pages/incidents/components/index/progress-rail"

export function ActionPanel({
  title,
  icon: Icon,
  items,
}: {
  title: string
  icon: TablerIcon
  items: IncidentAction[]
}) {
  const doneCount = items.filter((a) => a.status === "done").length
  const isEmpty = items.length === 0

  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <header className="flex items-center justify-between px-4 pt-3.5 pb-2.5">
        <div className="flex items-center gap-2">
          <Icon className="size-3.5 text-muted-foreground" strokeWidth={1.75} />
          <h3 className="text-[12px] font-semibold uppercase tracking-[0.12em] text-foreground">
            {title}
          </h3>
        </div>
        <AddActionDialog />
      </header>
      <div className="px-4 pb-2">
        <ProgressRail done={doneCount} total={items.length} />
      </div>
      {!isEmpty && (
        <div className="px-4 pt-2 pb-3">
          {items.map((action) => (
            <ActionItem key={action.id} action={action} />
          ))}
        </div>
      )}
      {isEmpty && (
        <div className="px-4 pb-4 text-[12px] text-muted-foreground/70">
          None yet.
        </div>
      )}
    </section>
  )
}
