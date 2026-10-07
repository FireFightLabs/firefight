import { router } from "@inertiajs/react"
import { IconAlertTriangle, IconClock, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { ApplyFix } from "@/components/investigations/apply-fix"
import { CancelFix } from "@/components/investigations/cancel-fix"
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
import { useExpiresIn } from "@/hooks/use-expires-in"
import { formatTime } from "@/lib/formatters"
import { APPROVED_CALL_ACTIONS, REMEDIATION_STEP_STATUS_DONE } from "@/lib/generated/constants"
import {
  investigationFixStepAskAgainPath, investigationFixStepDismissPath, investigationFixStepDonePath, investigationFixStepRunPath,
} from "@/lib/routes"
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
  if (fix.cancelledBy) {
    return `${status} by ${fix.cancelledBy}${fix.cancelledAt ? ` at ${formatTime(fix.cancelledAt)}` : ""}`
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

// A step an approval rule held, once approved. Approving it never ran it, so it asks to be run, under how things stand
// now as Halon just read them, for as long as the approval lasts. The server ships what is offered and why each is
// blocked.
function ApprovedStep({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
  const [ sending, setSending ] = useState<string | null>(null)
  const expiry = useExpiresIn(step.lapsed ? null : step.expiresAt)
  const offers = expiry.expired ? [] : step.offers
  const blocked = offers.includes(APPROVED_CALL_ACTIONS.RUN) ? step.runBlockedReason : step.askAgainBlockedReason

  function send(action: string, path: string) {
    setSending(action)
    router.post(path, {}, { preserveScroll: true, onFinish: () => setSending(null) })
  }

  function run() {
    send(APPROVED_CALL_ACTIONS.RUN, investigationFixStepRunPath(investigationId, step.id))
  }

  function dismiss() {
    send(APPROVED_CALL_ACTIONS.DISMISS, investigationFixStepDismissPath(investigationId, step.id))
  }

  function askAgain() {
    send(APPROVED_CALL_ACTIONS.ASK_AGAIN, investigationFixStepAskAgainPath(investigationId, step.id))
  }

  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-border bg-surface-selected px-2.5 py-2 text-xs">
      <span className="font-medium text-fg-primary">{approvedHeadline(step, expiry.expired)}</span>
      {step.checking && (
        <span className="flex items-center gap-1.5 text-fg-secondary">
          <IconLoader2 className="size-3.5 shrink-0 motion-safe:animate-spin" />
          Halon is checking how things stand now. Run waits until it has.
        </span>
      )}
      {step.warning && !step.checking && !step.lapsed && (
        <span className="flex items-start gap-1.5 font-medium text-warning">
          <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
          {step.warning}
        </span>
      )}
      {step.state && !step.checking && !step.lapsed && (
        <span className="text-fg-body">
          <span className="font-medium">Now: </span>
          {step.state}
        </span>
      )}
      <div className="flex flex-wrap items-center gap-2">
        {offers.includes(APPROVED_CALL_ACTIONS.RUN) && (
          <Button type="button" size="sm" disabled={step.runBlockedReason != null || sending != null} onClick={run}>
            {sending === APPROVED_CALL_ACTIONS.RUN && <IconLoader2 className="motion-safe:animate-spin" />}
            Run
          </Button>
        )}
        {offers.includes(APPROVED_CALL_ACTIONS.ASK_AGAIN) && (
          <Button type="button" size="sm" variant="outline" disabled={step.askAgainBlockedReason != null || sending != null} onClick={askAgain}>
            Ask again
          </Button>
        )}
        {offers.includes(APPROVED_CALL_ACTIONS.DISMISS) && (
          <Button type="button" size="sm" variant="outline" disabled={step.dismissBlockedReason != null || sending != null} onClick={dismiss}>
            Dismiss
          </Button>
        )}
        {expiry.label && (
          <span className="flex items-center gap-1 text-fg-muted">
            <IconClock className="size-3.5" />
            {expiry.label}
          </span>
        )}
      </div>
      {blocked && !step.checking && <span className="text-fg-muted">{blocked}</span>}
    </div>
  )
}

function approvedHeadline(step: InvestigationRemediationStep, expired: boolean): string {
  const who = step.approvedBy ?? "An approver"
  if (step.lapsed || expired) {
    return `${who} approved it, but nobody ran it within the hour, so the approval expired.`
  }
  return `${who} approved it. Run it now?`
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
        {step.offers.length > 0 && <ApprovedStep investigationId={investigationId} step={step} />}
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
      <CancelFix investigationId={investigationId} fix={fix} />
      <UndoFix investigationId={investigationId} fix={fix} />
    </div>
  )
}
