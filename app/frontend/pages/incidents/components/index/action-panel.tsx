import { useEffect } from "react"
import { usePoll } from "@inertiajs/react"

import type { IncidentPageProp } from "@/pages/incidents/lib/after-mutation"
import type { IncidentAction } from "@/pages/incidents/types"
import type { InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { ActionItem } from "@/pages/incidents/components/index/action-item"
import { AddActionDialog } from "@/pages/incidents/components/index/add-action-dialog"
import { ProgressRail } from "@/pages/incidents/components/index/progress-rail"

const ISSUE_POLL_MS = 3000
const ITEMS: IncidentPageProp[] = ["actions"]

export function ActionPanel({
  title,
  items,
  blockedReason,
  incidentId,
  actionType,
  candidates,
  canEdit,
}: {
  title: string
  items: IncidentAction[]
  blockedReason?: string
  incidentId: string
  actionType: "action" | "followup"
  candidates: InlineChoice[]
  canEdit: boolean
}) {
  const canAdd = !blockedReason
  const doneCount = items.filter((item) => item.status === "done").length
  const isEmpty = items.length === 0
  const issueOpening = items.some((item) => item.issueOpening)

  const { start, stop } = usePoll(ISSUE_POLL_MS, { only: ITEMS }, { autoStart: false })

  // An issue is opened in a job, so the items are read again until it is there.
  useEffect(() => {
    if (!issueOpening) {
      return
    }
    start()
    return stop
  }, [issueOpening, start, stop])

  // The empty and the filled panel share one header, so the add dialog stays mounted, with what was typed in it, when
  // the first item arrives from elsewhere while it is open.
  return (
    <section className={`rounded-xl border border-border bg-card transition-opacity ${isEmpty ? "" : "overflow-hidden"} ${canAdd ? "" : "opacity-50"}`}>
      <header className={`flex items-center justify-between ${isEmpty ? "px-4 py-2" : "px-5 pt-6 pb-2.5"}`}>
        {isEmpty ? (
          <span className="text-[12px] text-muted-foreground">
            {title} · None yet
          </span>
        ) : (
          <h3 className="text-[12px] font-semibold uppercase tracking-[0.10em] text-fg-primary">
            {title}
          </h3>
        )}
        <AddActionDialog disabled={!canAdd} incidentId={incidentId} actionType={actionType} disabledTooltip={blockedReason} />
      </header>
      {!isEmpty && (
        <>
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
        </>
      )}
    </section>
  )
}
