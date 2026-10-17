import { type Icon, IconAlertTriangle, IconCheck, IconChevronDown, IconCircleDashed, IconClock, IconExternalLink, IconLoader2, IconX } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { DetailList } from "@/components/detail-list"
import { useExpiresIn } from "@/hooks/use-expires-in"
import { formatTime, withLocalMoments } from "@/lib/formatters"
import { APPROVED_CALL_ACTIONS, CHANGE_STAGE_STATUSES, HELD_CALL_STATUSES } from "@/lib/generated/constants"
import { agentChatHeldCallAskAgainPath, agentChatHeldCallDismissPath, agentChatHeldCallRunPath } from "@/lib/routes"
import { sendHeldCallAction } from "@/pages/agent/lib/chat-updates"
import type { AgentChatHeldCall } from "@/types/serializers"

interface HeldCallCardProps {
  conversationId: string
  heldCall: AgentChatHeldCall
}

const OPEN_STATUSES: AgentChatHeldCall["status"][] = [ HELD_CALL_STATUSES.CHECKING, HELD_CALL_STATUSES.READY ]

type Stage = AgentChatHeldCall["stages"][number]

const STAGE_ICONS: Record<Stage["status"], { icon: Icon; className: string }> = {
  [CHANGE_STAGE_STATUSES.PENDING]: { icon: IconCircleDashed, className: "text-ink-3" },
  [CHANGE_STAGE_STATUSES.RUNNING]: { icon: IconLoader2, className: "text-ink-2 motion-safe:animate-spin" },
  [CHANGE_STAGE_STATUSES.DONE]: { icon: IconCheck, className: "text-success" },
  [CHANGE_STAGE_STATUSES.FAILED]: { icon: IconX, className: "text-danger" },
}

// A call Halon made that an approval rule held for someone else. It says what Halon wants to do and who may approve it,
// and approving it runs it, so the card then follows the run as a checklist and says how it went, with the page it made.
// A call approved before approving ran it still asks to be run, under how things stand now as Halon just read them. The
// server ships what is offered and why each is blocked, so the card decides nothing. What the call was given sits under
// Details.
export function HeldCallCard({ conversationId, heldCall }: HeldCallCardProps) {
  const [ sending, setSending ] = useState<string | null>(null)
  const [ detailsOpen, setDetailsOpen ] = useState(false)
  const open = OPEN_STATUSES.includes(heldCall.status)
  const expiry = useExpiresIn(open ? heldCall.expiresAt : null)
  const checking = heldCall.status === HELD_CALL_STATUSES.CHECKING
  const rows = heldCall.rows.map(([ label, meta ]) => ({ label, meta }))
  const details = heldCall.asked.map(([ label, meta ]) => ({ label, meta: withLocalMoments(meta) }))
  const offers = expiry.expired ? [] : heldCall.offers
  const blocked = offers.includes(APPROVED_CALL_ACTIONS.RUN) ? heldCall.runBlockedReason : heldCall.askAgainBlockedReason

  function send(action: string, path: string) {
    setSending(action)
    sendHeldCallAction(path, { onFinish: doneSending })
  }

  function doneSending() {
    setSending(null)
  }

  function toggleDetails() {
    setDetailsOpen((current) => !current)
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
        {!checking && <p className="text-[13px] leading-relaxed text-ink-2 [overflow-wrap:anywhere]">{heldCall.line}</p>}
      </div>
      {heldCall.status === HELD_CALL_STATUSES.WAITING && rows.length > 0 && <DetailList details={rows} />}
      {heldCall.stages.length > 0 && (
        <ul className="flex flex-col gap-1.5">
          {heldCall.stages.map((stage) => (
            <ChangeStage key={stage.key} stage={stage} />
          ))}
        </ul>
      )}
      {heldCall.status === HELD_CALL_STATUSES.RAN && heldCall.link && (
        <a href={heldCall.link} target="_blank" rel="noreferrer" className="flex w-fit items-center gap-1 text-[13px] text-accent-ink hover:underline">
          {heldCall.link.replace(/^https?:\/\//, "")}
          <IconExternalLink className="size-3" />
        </a>
      )}
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
      {(offers.length > 0 || expiry.label || details.length > 0) && (
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
          {details.length > 0 && (
            <button
              type="button"
              aria-expanded={detailsOpen}
              onClick={toggleDetails}
              className="ml-auto flex items-center gap-1 rounded-control px-1.5 py-1 text-[12.5px] text-ink-2 transition-colors duration-150 hover:bg-hover-2 hover:text-ink"
            >
              Details
              <IconChevronDown className={`size-3.5 transition-transform duration-150 ${detailsOpen ? "rotate-180" : ""}`} />
            </button>
          )}
        </div>
      )}
      {detailsOpen && (
        <div className="flex flex-col gap-2 border-t border-line pt-3">
          <p className="text-[12.5px] text-ink-2 [overflow-wrap:anywhere]">{[ heldCall.callName, heldCall.target ].filter(Boolean).join(" on ")}</p>
          <DetailList details={details} />
        </div>
      )}
      {blocked && !checking && <p className="text-[12.5px] text-ink-3">{blocked}</p>}
    </section>
  )
}

// One part of a code change: how it stands, with a line on how far it got.
function ChangeStage({ stage }: { stage: Stage }) {
  const mark = STAGE_ICONS[stage.status]
  const Mark = mark.icon

  return (
    <li className="flex items-start gap-2 text-[13px] leading-relaxed">
      <Mark className={`mt-1 size-3.5 shrink-0 ${mark.className}`} aria-label={stage.status} />
      <div className="flex min-w-0 flex-col [overflow-wrap:anywhere]">
        <span className="font-medium text-ink">{stage.title}</span>
        {stage.detail && <span className="text-[12.5px] text-ink-3">{stage.detail}</span>}
      </div>
    </li>
  )
}
