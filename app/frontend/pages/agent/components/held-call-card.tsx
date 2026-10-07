import { router } from "@inertiajs/react"
import { IconAlertTriangle, IconClock, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import DetailList from "@/components/agent-ui/detail-list"
import { useExpiresIn } from "@/hooks/use-expires-in"
import { formatTime } from "@/lib/formatters"
import { APPROVED_CALL_ACTIONS, HELD_CALL_STATUSES } from "@/lib/generated/constants"
import { agentChatHeldCallAskAgainPath, agentChatHeldCallDismissPath, agentChatHeldCallRunPath } from "@/lib/routes"
import { refreshHeldCalls } from "@/pages/agent/lib/chat-updates"
import type { AgentChatHeldCall } from "@/types/serializers"

interface HeldCallCardProps {
  conversationId: string
  heldCall: AgentChatHeldCall
}

const OPEN_STATUSES: string[] = [ HELD_CALL_STATUSES.CHECKING, HELD_CALL_STATUSES.READY ]

// A call Halon made that an approval rule held for someone else. Approving it never ran it, so once approved the card
// asks to run it, under how things stand now as Halon just read them. Nothing runs until Run is pressed, and the
// approval lasts an hour. The server ships what is offered and why each is blocked, so the card decides nothing.
export function HeldCallCard({ conversationId, heldCall }: HeldCallCardProps) {
  const [ sending, setSending ] = useState<string | null>(null)
  const open = OPEN_STATUSES.includes(heldCall.status)
  const expiry = useExpiresIn(open ? heldCall.expiresAt : null)
  const checking = heldCall.status === HELD_CALL_STATUSES.CHECKING
  const details = heldCall.asked.map(([ label, meta ]) => ({ label, meta }))
  const offers = expiry.expired ? [] : heldCall.offers
  const blocked = offers.includes(APPROVED_CALL_ACTIONS.RUN) ? heldCall.runBlockedReason : heldCall.askAgainBlockedReason

  function send(action: string, path: string) {
    setSending(action)
    router.post(path, {}, { preserveScroll: true, preserveState: true, onSuccess: refreshHeldCalls, onFinish: () => setSending(null) })
  }

  function run() {
    send(APPROVED_CALL_ACTIONS.RUN, agentChatHeldCallRunPath(conversationId, heldCall.id))
  }

  function dismiss() {
    send(APPROVED_CALL_ACTIONS.DISMISS, agentChatHeldCallDismissPath(conversationId, heldCall.id))
  }

  function askAgain() {
    send(APPROVED_CALL_ACTIONS.ASK_AGAIN, agentChatHeldCallAskAgainPath(conversationId, heldCall.id))
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Approved call">
      <div className="flex flex-col gap-1">
        <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{heldCall.headline}</h3>
        {heldCall.target && <p className="text-[12.5px] text-ink-2">{heldCall.callName}</p>}
      </div>
      {checking && (
        <p className="flex items-center gap-1.5 text-[13px] text-ink-2">
          <IconLoader2 className="size-3.5 shrink-0 motion-safe:animate-spin" />
          Halon is checking how things stand now. Run waits until it has.
        </p>
      )}
      {heldCall.status === HELD_CALL_STATUSES.READY && heldCall.warning && (
        <p className="flex items-start gap-1.5 text-[13px] font-medium text-warning">
          <IconAlertTriangle className="mt-0.5 size-3.5 shrink-0" />
          {heldCall.warning}
        </p>
      )}
      {heldCall.status === HELD_CALL_STATUSES.READY && heldCall.state && (
        <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">
          <span className="font-medium">Now: </span>
          {heldCall.state}
          {heldCall.checkedAt && <span className="text-ink-3"> (checked at {formatTime(heldCall.checkedAt)})</span>}
        </p>
      )}
      {details.length > 0 && <DetailList details={details} />}
      {heldCall.result && (
        <pre className="max-h-40 overflow-auto rounded-md border border-border bg-surface-code px-2.5 py-2 font-mono text-xs whitespace-pre-wrap text-fg-body">
          {heldCall.result}
        </pre>
      )}
      {decidedLine(heldCall) && <p className="text-[12.5px] text-ink-3">{decidedLine(heldCall)}</p>}
      {(offers.length > 0 || expiry.label) && (
        <div className="flex flex-wrap items-center gap-2">
          {offers.includes(APPROVED_CALL_ACTIONS.RUN) && (
            <Button size="sm" variant="primary" disabled={heldCall.runBlockedReason != null || sending != null} onClick={run}>
              {sending === APPROVED_CALL_ACTIONS.RUN && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              Run
            </Button>
          )}
          {offers.includes(APPROVED_CALL_ACTIONS.DISMISS) && (
            <Button size="sm" variant="secondary" disabled={heldCall.dismissBlockedReason != null || sending != null} onClick={dismiss}>
              Dismiss
            </Button>
          )}
          {offers.includes(APPROVED_CALL_ACTIONS.ASK_AGAIN) && (
            <Button size="sm" variant="secondary" disabled={heldCall.askAgainBlockedReason != null || sending != null} onClick={askAgain}>
              {sending === APPROVED_CALL_ACTIONS.ASK_AGAIN && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              Ask again
            </Button>
          )}
          {expiry.label && (
            <span className="flex items-center gap-1 text-[12.5px] text-ink-3">
              <IconClock className="size-3.5" />
              {expiry.label}
            </span>
          )}
        </div>
      )}
      {blocked && !checking && <p className="text-[12.5px] text-ink-3">{blocked}</p>}
    </section>
  )
}

function decidedLine(heldCall: AgentChatHeldCall): string | null {
  if (!heldCall.decidedBy) {
    return null
  }
  if (heldCall.status === HELD_CALL_STATUSES.DISMISSED) {
    return `Dismissed by ${heldCall.decidedBy}`
  }
  return `Run by ${heldCall.decidedBy}`
}
