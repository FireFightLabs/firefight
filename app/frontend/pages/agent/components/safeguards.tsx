import { IconClockHour4, IconDatabase, IconDownload, IconLoader2, IconUserQuestion } from "@tabler/icons-react"
import { useState } from "react"

import { Button, buttonVariants } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { DATA_WRITE_KINDS, MITIGATION_STATUSES, OWNER_ASK_STATUSES } from "@/lib/generated/constants"
import { agentChatDataRepairCopyPath } from "@/lib/routes"
import { extendMitigation, keepMitigation, undoMitigation } from "@/pages/agent/lib/chat-updates"
import type { AgentChatDataRepair, AgentChatMitigation, AgentChatOwnerAsk } from "@/types/serializers"

const CARD_CLASS = "flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card"

interface SafeguardsProps {
  conversationId: string
  repairs: AgentChatDataRepair[] | undefined
  mitigations: AgentChatMitigation[] | undefined
  ownerAsks: AgentChatOwnerAsk[] | undefined
}

// What Firefight did around a change Halon made in this chat, each where it happened: the rows a statement changed
// with its copy, a temporary change and when it is undone, and the owner asked before something they started was stopped.
export function Safeguards({ conversationId, repairs, mitigations, ownerAsks }: SafeguardsProps) {
  return (
    <>
      {ownerAsks?.map((ask) => <OwnerAskCard key={ask.id} ask={ask} />)}
      {repairs?.map((repair) => <DataRepairCard key={repair.id} conversationId={conversationId} repair={repair} />)}
      {mitigations?.map((mitigation) => <MitigationCard key={mitigation.id} conversationId={conversationId} mitigation={mitigation} />)}
    </>
  )
}

function checkWords(repair: AgentChatDataRepair): string | null {
  if (repair.checkError) {
    return `The check could not run afterwards: ${repair.checkError}`
  }
  if (repair.wrongAfter == null) {
    return null
  }
  if (repair.wrongAfter === 0) {
    return `Check: ${repair.wrongBefore ?? 0} wrong before, none now.`
  }
  return `Check: ${repair.wrongAfter} still wrong, ${repair.wrongBefore ?? 0} before. The repair did not finish.`
}

// A statement that changed rows: how many, the check before and after, and the copy of the rows as they were, which
// downloads as a file while it is kept.
function DataRepairCard({ conversationId, repair }: { conversationId: string; repair: AgentChatDataRepair }) {
  const check = checkWords(repair)
  return (
    <section className={CARD_CLASS} aria-label="Data change">
      <div className="flex items-start gap-2">
        <IconDatabase className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">Changed {repair.rows}</h3>
          {check && <p className="text-[13px] leading-snug text-ink-2">{check}</p>}
        </div>
      </div>
      {repair.copyKeptUntil ? (
        <div className="flex flex-wrap items-center gap-2">
          <a href={agentChatDataRepairCopyPath(conversationId, repair.id)} className={buttonVariants({ variant: "secondary", size: "sm" })} download>
            <IconDownload className="size-3.5" />
            Download the rows as they were
          </a>
          <span className="text-[12.5px] text-ink-3">Kept until {formatDateTime(repair.copyKeptUntil)}</span>
        </div>
      ) : (
        repair.kind !== DATA_WRITE_KINDS.INSERT && <p className="text-[12.5px] text-ink-3">The copy of these rows is no longer kept.</p>
      )}
    </section>
  )
}

function mitigationState(mitigation: AgentChatMitigation): string {
  if (mitigation.status === MITIGATION_STATUSES.ACTIVE && mitigation.expiresAt) {
    return `Firefight undoes this at ${formatTime(mitigation.expiresAt)} unless someone keeps it.`
  }
  if (mitigation.status === MITIGATION_STATUSES.KEPT) {
    return "Kept. Firefight will not undo it."
  }
  if (mitigation.status === MITIGATION_STATUSES.UNDOING) {
    return "Undoing it now."
  }
  return mitigation.outcome ?? ""
}

// A change customers feel, such as a feature flag turned off. While it is in place it says when Firefight undoes it and
// offers Keep it, One more hour and Undo now, each blocked with why when this viewer may not. Undo now asks first.
function MitigationCard({ conversationId, mitigation }: { conversationId: string; mitigation: AgentChatMitigation }) {
  const [ sending, setSending ] = useState<string | null>(null)
  const [ confirming, setConfirming ] = useState(false)
  const live = mitigation.status === MITIGATION_STATUSES.ACTIVE || mitigation.status === MITIGATION_STATUSES.KEPT
  const active = mitigation.status === MITIGATION_STATUSES.ACTIVE
  const blocked = mitigation.undoBlockedReason ?? (active ? mitigation.keepBlockedReason : null)

  function doneSending() {
    setSending(null)
  }

  function keep() {
    setSending("keep")
    keepMitigation(conversationId, mitigation.id, { onFinish: doneSending })
  }

  function giveMoreTime() {
    setSending("extend")
    extendMitigation(conversationId, mitigation.id, { onFinish: doneSending })
  }

  function askToUndo() {
    setConfirming(true)
  }

  function cancelUndo() {
    setConfirming(false)
  }

  function undo() {
    setConfirming(false)
    setSending("undo")
    undoMitigation(conversationId, mitigation.id, { onFinish: doneSending })
  }

  return (
    <section className={CARD_CLASS} aria-label="Temporary change">
      <div className="flex items-start gap-2">
        <IconClockHour4 className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{mitigation.title}</h3>
          <p className="text-[12.5px] text-ink-2 [overflow-wrap:anywhere]">{mitigation.label}</p>
          <p className="text-[13px] leading-snug text-ink [overflow-wrap:anywhere]">{mitigationState(mitigation)}</p>
          {live && mitigation.undoNote && <p className="text-[12.5px] leading-snug text-ink-3 [overflow-wrap:anywhere]">Undo: {mitigation.undoNote}</p>}
        </div>
      </div>
      {live && (
        <div className="flex flex-wrap items-center gap-2">
          {active && (
            <Button size="sm" variant="secondary" disabled={mitigation.keepBlockedReason != null || sending != null} onClick={keep}>
              {sending === "keep" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              Keep it
            </Button>
          )}
          {active && (
            <Button size="sm" variant="secondary" disabled={mitigation.extendBlockedReason != null || sending != null} onClick={giveMoreTime}>
              {sending === "extend" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              One more hour
            </Button>
          )}
          <Button size="sm" variant="secondary" disabled={mitigation.undoBlockedReason != null || sending != null} onClick={askToUndo}>
            {sending === "undo" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Undo now
          </Button>
          {blocked && <span className="text-[12.5px] text-ink-3">{blocked}</span>}
        </div>
      )}
      <ConfirmDeleteDialog
        open={confirming}
        title="Undo it now?"
        description={`Firefight puts back what this changed, as the person who asked for it, and says how it went here. ${mitigation.undoNote ?? ""}`.trim()}
        confirmLabel="Undo now"
        onConfirm={undo}
        onCancel={cancelUndo}
      />
    </section>
  )
}

const OWNER_ASK_WORDS: Record<string, (ask: AgentChatOwnerAsk) => string> = {
  [OWNER_ASK_STATUSES.ASKED]: (ask) => `Waiting for ${ask.ownerName} to agree. It runs only once they do.`,
  [OWNER_ASK_STATUSES.AGREED]: (ask) => `${ask.ownerName} agreed.`,
  [OWNER_ASK_STATUSES.DECLINED]: (ask) => `${ask.ownerName} said no, so it was not run.`,
  [OWNER_ASK_STATUSES.WITHDRAWN]: () => "No longer needed, so it was not run.",
}

// Whoever started what a confirmed call would stop, asked in their direct messages, and what they answered.
function OwnerAskCard({ ask }: { ask: AgentChatOwnerAsk }) {
  return (
    <section className={CARD_CLASS} aria-label="Owner asked">
      <div className="flex items-start gap-2">
        <IconUserQuestion className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{ask.headline}</h3>
          <p className="text-[13px] leading-snug text-ink-2">{OWNER_ASK_WORDS[ask.status]?.(ask)}</p>
        </div>
      </div>
    </section>
  )
}
