import { ApplyFix } from "@/components/investigations/apply-fix"
import { CancelFix } from "@/components/investigations/cancel-fix"
import { FixStep } from "@/components/investigations/fix-step"
import { UndoFix } from "@/components/investigations/undo-fix"
import { FIX_STATUS_LABELS, UNDO_STATUS_LABELS } from "@/components/investigations/labels"
import { formatTime } from "@/lib/formatters"
import type { InvestigationRemediationPlan } from "@/types/serializers"

function appliedLine(fix: InvestigationRemediationPlan): string | undefined {
  const status = (fix.isUndo ? UNDO_STATUS_LABELS : FIX_STATUS_LABELS)[fix.status]
  if (!status) {
    return undefined
  }
  if (fix.cancelledBy) {
    return `${status} by ${fix.cancelledBy}${fix.cancelledAt ? ` at ${formatTime(fix.cancelledAt)}` : ""}`
  }
  return fix.appliedBy ? `${status}, started by ${fix.appliedBy}${fix.appliedAt ? ` at ${formatTime(fix.appliedAt)}` : ""}` : status
}

// How to fix what the run found, step by step, with how to undo each and how to tell it worked. A fix that runs through
// a connection is applied from here, and each step then says how it went.
export function FixPlan({ investigationId, fix }: { investigationId: string; fix: InvestigationRemediationPlan }) {
  const applied = appliedLine(fix)

  return (
    <div className="flex flex-col gap-3">
      <p className="text-fg-primary">{fix.summary}</p>
      <ol className="flex flex-col gap-2.5">
        {fix.steps.map((step) => (
          <FixStep key={step.id} investigationId={investigationId} step={step} />
        ))}
      </ol>
      {fix.verify && <p className="text-xs text-fg-secondary">How to tell it worked: {fix.verify}</p>}
      {applied && <p className="text-xs font-medium text-fg-body">{applied}</p>}
      {fix.unattendedReading && (
        <div className="text-xs text-fg-secondary">
          <p>Halon applied it on its own, under the team&apos;s unattended rules:</p>
          <p className="whitespace-pre-line">{fix.unattendedReading}</p>
        </div>
      )}
      {fix.appliable && <ApplyFix investigationId={investigationId} fix={fix} />}
      <CancelFix investigationId={investigationId} fix={fix} />
      <UndoFix investigationId={investigationId} fix={fix} />
    </div>
  )
}
