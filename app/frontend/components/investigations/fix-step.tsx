import { IconAlertTriangle } from "@tabler/icons-react"

import { CodeFixWorkView } from "@/components/code-fix-work"
import { ApprovedStep } from "@/components/investigations/approved-step"
import { FixStepStatus } from "@/components/investigations/fix-step-status"
import { REMEDIATION_STEP_LABELS, receiptLine } from "@/components/investigations/labels"
import { MarkDone } from "@/components/investigations/mark-done"
import { REMEDIATION_STEP_STATUS_RUNNING } from "@/lib/generated/constants"
import type { InvestigationRemediationStep } from "@/types/serializers"

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

function receipt(step: InvestigationRemediationStep): string | undefined {
  return step.receipt ? receiptLine(step.receipt) : undefined
}

// One step of a fix, with how to undo it, how it went and what may be done with it now.
export function FixStep({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const status = step.statusLabel

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
        {step.progress && (
          <CodeFixWorkView
            work={step.progress}
            running={step.status === REMEDIATION_STEP_STATUS_RUNNING}
            questionBlockedReason={step.questionBlockedReason}
            questionChangeBlockedReason={step.questionChangeBlockedReason ?? null}
            pauseBlockedReason={step.pauseBlockedReason ?? null}
          />
        )}
        {step.result && !step.progress && (
          <pre className="max-h-40 overflow-auto rounded-md border border-border bg-surface-code px-2.5 py-2 font-mono text-xs whitespace-pre-wrap text-fg-body">
            {step.result}
          </pre>
        )}
        {step.offers.length > 0 && <ApprovedStep investigationId={investigationId} step={step} />}
        {receipt(step) && <span className="text-xs text-fg-muted">{receipt(step)}</span>}
        {step.markDoneBlockedReason == null && <MarkDone investigationId={investigationId} step={step} />}
      </div>
    </li>
  )
}
