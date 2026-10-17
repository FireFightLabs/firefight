import { IconCircleCheck, IconClockHour4, IconDatabase, IconDownload, IconLoader2, IconUserQuestion } from "@tabler/icons-react"
import { useState } from "react"

import { Button, buttonVariants } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { DATA_WRITE_KINDS, MITIGATION_STATUSES, MITIGATION_UNDO_STATES, OWNER_ASK_STATUSES } from "@/lib/generated/constants"
import { agentChatDataRepairCopyPath } from "@/lib/routes"
import { extendMitigation, keepMitigation, markMitigationBack, undoMitigation } from "@/pages/agent/lib/chat-updates"
import type { AgentChatDataRepair, AgentChatMitigation, AgentChatOwnerAsk } from "@/types/serializers"

const CARD_CLASS = "flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card"
const PUTS_BACK = "Firefight puts back what this changed, as the person who asked for it, and says how it went here."
const ASKS_HALON = "Halon is asked in this chat to put back what this changed. Its call asks first, and you mark it once it's back."

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
    const at = formatTime(mitigation.expiresAt)
    return mitigation.asksHalon
      ? `Halon asks in this chat to put it back at ${at} unless someone keeps it.`
      : `Firefight undoes this at ${at} unless someone keeps it.`
  }
  if (mitigation.status === MITIGATION_STATUSES.KEPT) {
    return "Kept, so it is not put back."
  }
  if (mitigation.status === MITIGATION_STATUSES.UNDO_ASKED) {
    return "Halon was asked to put this back. Mark it once it's back."
  }
  if (mitigation.status === MITIGATION_STATUSES.MADE) {
    return mitigation.unaskedWords ?? ""
  }
  if (mitigation.status === MITIGATION_STATUSES.UNDOING) {
    return "Undoing it now."
  }
  return mitigation.outcome ?? ""
}

// Why Halon made a change customers feel without asking, said beside when it is undone.
function unaskedLine(mitigation: AgentChatMitigation): string | null {
  return mitigation.status === MITIGATION_STATUSES.MADE ? null : mitigation.unaskedWords ?? null
}

// A change customers feel, such as a feature flag turned off. While it is in place it says when it is put back, by
// Firefight or by Halon asked in the chat, and offers Keep it, One more hour and Undo now, each blocked with why when
// this viewer may not. Undo now asks first. Once Halon was asked to put it back it offers It's back, which a person
// presses once it is, and Undo now to ask again.
// A change Halon made without asking says why and offers Undo now alone, or nothing when nothing puts it back.
function MitigationCard({ conversationId, mitigation }: { conversationId: string; mitigation: AgentChatMitigation }) {
  const [ sending, setSending ] = useState<string | null>(null)
  const [ confirming, setConfirming ] = useState(false)
  const [ confirmingBack, setConfirmingBack ] = useState(false)
  const made = mitigation.status === MITIGATION_STATUSES.MADE
  const live = mitigation.status === MITIGATION_STATUSES.ACTIVE || mitigation.status === MITIGATION_STATUSES.KEPT ||
    mitigation.status === MITIGATION_STATUSES.UNDO_ASKED || made
  const active = mitigation.status === MITIGATION_STATUSES.ACTIVE
  const asked = mitigation.status === MITIGATION_STATUSES.UNDO_ASKED
  const undoable = mitigation.undoState !== MITIGATION_UNDO_STATES.NO_INVERSE
  const blocked = undoable ? mitigation.undoBlockedReason ?? (active ? mitigation.keepBlockedReason : null) : null
  const because = unaskedLine(mitigation)
  const Icon = made ? IconCircleCheck : IconClockHour4

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

  function askToMarkBack() {
    setConfirmingBack(true)
  }

  function cancelMarkBack() {
    setConfirmingBack(false)
  }

  function markBack() {
    setConfirmingBack(false)
    setSending("back")
    markMitigationBack(conversationId, mitigation.id, { onFinish: doneSending })
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
    <section className={CARD_CLASS} aria-label={made ? "Change made without asking" : "Temporary change"}>
      <div className="flex items-start gap-2">
        <Icon className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{mitigation.title}</h3>
          <p className="text-[12.5px] text-ink-2 [overflow-wrap:anywhere]">{mitigation.label}</p>
          <p className="text-[13px] leading-snug text-ink [overflow-wrap:anywhere]">{mitigationState(mitigation)}</p>
          {because && <p className="text-[12.5px] leading-snug text-ink-2 [overflow-wrap:anywhere]">{because}</p>}
          {made && !undoable && <p className="text-[12.5px] leading-snug text-ink-3">There is no Undo for this change.</p>}
          {live && mitigation.undoNote && <p className="text-[12.5px] leading-snug text-ink-3 [overflow-wrap:anywhere]">Undo: {mitigation.undoNote}</p>}
        </div>
      </div>
      {live && (active || undoable) && (
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
          {asked && (
            <Button size="sm" variant="secondary" disabled={mitigation.backBlockedReason != null || sending != null} onClick={askToMarkBack}>
              {sending === "back" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              It&apos;s back
            </Button>
          )}
          {undoable && (
            <Button size="sm" variant="secondary" disabled={mitigation.undoBlockedReason != null || sending != null} onClick={askToUndo}>
              {sending === "undo" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              Undo now
            </Button>
          )}
          {blocked && <span className="text-[12.5px] text-ink-3">{blocked}</span>}
        </div>
      )}
      <ConfirmDeleteDialog
        open={confirming}
        title="Undo it now?"
        description={mitigation.asksHalon ? ASKS_HALON : `${PUTS_BACK} ${mitigation.undoNote ?? ""}`.trim()}
        confirmLabel="Undo now"
        onConfirm={undo}
        onCancel={cancelUndo}
      />
      <ConfirmDeleteDialog
        open={confirmingBack}
        title={`Mark ${mitigation.title} as back?`}
        description="Firefight stops tracking it."
        confirmLabel="It's back"
        confirmVariant="default"
        onConfirm={markBack}
        onCancel={cancelMarkBack}
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
