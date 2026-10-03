import { router } from "@inertiajs/react"
import { IconAlertTriangle, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { ApplyFix } from "@/components/investigations/apply-fix"
import { FixStepStatus } from "@/components/investigations/fix-step-status"
import { UndoFix } from "@/components/investigations/undo-fix"
import {
  DECISION_LABELS,
  FIX_STATUS_LABELS,
  UNDO_STATUS_LABELS,
  FIX_STEP_STATUS_LABELS,
  REMEDIATION_STEP_LABELS,
  labelFor,
} from "@/components/investigations/labels"
import { Button } from "@/components/ui/button"
import { formatTime } from "@/lib/formatters"
import { REMEDIATION_STEP_STATUS_DONE } from "@/lib/generated/constants"
import { investigationFixStepDonePath } from "@/lib/routes"
import type { InvestigationRemediationPlan, InvestigationRemediationStep } from "@/types/serializers"

// Step numbers read as a list, such as "1, 2 and 3".
function listed(numbers: number[]): string {
  const words = numbers.map(String)
  return words.length < 2 ? words.join("") : `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}`
}

function where(step: InvestigationRemediationStep): string | undefined {
  return step.repository ?? step.action
}

function after(step: InvestigationRemediationStep): string | undefined {
  if (step.dependsOn.length === 0) {
    return undefined
  }
  const steps = listed(step.dependsOn)
  return step.dependsOn.length === 1 ? `After step ${steps}` : `After steps ${steps}`
}

function stepStatus(step: InvestigationRemediationStep): string | null {
  if (step.status === REMEDIATION_STEP_STATUS_DONE && step.doneBy) {
    return `Done by ${step.doneBy}`
  }
  return FIX_STEP_STATUS_LABELS[step.status]
}

function receipt(step: InvestigationRemediationStep): string | undefined {
  return step.receipt ? `${labelFor(DECISION_LABELS, step.receipt.decision)} by the gateway at ${formatTime(step.receipt.at)}` : undefined
}

function appliedLine(fix: InvestigationRemediationPlan): string | undefined {
  const status = (fix.isUndo ? UNDO_STATUS_LABELS : FIX_STATUS_LABELS)[fix.status]
  if (!status) {
    return undefined
  }
  return fix.appliedBy ? `${status}, started by ${fix.appliedBy}${fix.appliedAt ? ` at ${formatTime(fix.appliedAt)}` : ""}` : status
}

// A step a person does rather than Firefight, done once they say so.
function MarkDone({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const [ marking, setMarking ] = useState(false)

  function markDone() {
    setMarking(true)
    router.post(investigationFixStepDonePath(investigationId, step.id), {}, { preserveScroll: true, onFinish: () => setMarking(false) })
  }

  return (
    <Button type="button" size="sm" variant="outline" className="w-fit" disabled={marking} onClick={markDone}>
      {marking && <IconLoader2 className="motion-safe:animate-spin" />}
      {marking ? "Marking done" : "Mark done"}
    </Button>
  )
}

function Step({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const status = stepStatus(step)

  return (
    <li className="flex gap-3 rounded-lg border border-border bg-background px-3 py-2.5">
      <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-surface-selected text-[11px] font-semibold tabular-nums text-fg-body">
        {step.position}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-fg-muted">
          <span className="font-medium uppercase tracking-wider">{REMEDIATION_STEP_LABELS[step.kind]}</span>
          {where(step) && <code className="truncate font-mono">{where(step)}</code>}
          {after(step) && <span>{after(step)}</span>}
        </span>
        <span className="text-fg-primary">{step.description}</span>
        {step.missing && (
          <span className="flex items-start gap-1.5 text-xs text-warning">
            <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
            Needs: {step.missing}
          </span>
        )}
        {step.undo && <span className="text-xs text-fg-secondary">To undo: {step.undo}</span>}
        {step.arguments && (
          <details className="text-xs text-fg-secondary">
            <summary className="w-fit cursor-pointer select-none hover:text-fg-primary">What it sends</summary>
            <pre className="mt-1.5 max-h-48 overflow-auto rounded-md border border-border bg-surface-code px-2.5 py-2 font-mono whitespace-pre-wrap text-fg-body">{step.arguments}</pre>
          </details>
        )}
        {status && <FixStepStatus status={step.status} label={status} />}
        {step.result && (
          <pre className="max-h-40 overflow-auto rounded-md border border-border bg-surface-code px-2.5 py-2 font-mono text-xs whitespace-pre-wrap text-fg-body">
            {step.result}
          </pre>
        )}
        {receipt(step) && <span className="text-xs text-fg-muted">{receipt(step)}</span>}
        {step.markDoneBlockedReason == null && <MarkDone investigationId={investigationId} step={step} />}
      </div>
    </li>
  )
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
          <Step key={step.id} investigationId={investigationId} step={step} />
        ))}
      </ol>
      {fix.verify && <p className="text-xs text-fg-secondary">How to tell it worked: {fix.verify}</p>}
      {applied && <p className="text-xs font-medium text-fg-body">{applied}</p>}
      {fix.appliable && <ApplyFix investigationId={investigationId} fix={fix} />}
      <UndoFix investigationId={investigationId} fix={fix} />
    </div>
  )
}
