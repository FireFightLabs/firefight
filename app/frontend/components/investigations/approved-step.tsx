import { router } from "@inertiajs/react"
import { IconAlertTriangle, IconClock, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { useExpiresIn } from "@/hooks/use-expires-in"
import { APPROVED_CALL_ACTIONS } from "@/lib/generated/constants"
import { investigationFixStepAskAgainPath, investigationFixStepDismissPath, investigationFixStepRunPath } from "@/lib/routes"
import type { InvestigationRemediationStep } from "@/types/serializers"

function approvedHeadline(step: InvestigationRemediationStep, expired: boolean): string {
  if ((step.lapsed || expired) && step.lapsedReason) {
    return step.lapsedReason
  }
  return `${step.approvedBy ?? "An approver"} approved it. Run it now?`
}

// A step an approval rule held, once approved. Approving it never ran it, so it asks to be run, under how things stand
// now as Halon just read them, for as long as the approval lasts. The server ships what is offered and why each is
// blocked.
export function ApprovedStep({ investigationId, step }: { investigationId: string; step: InvestigationRemediationStep }) {
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
