import { IconLoader2, IconPlayerPause } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { CODE_FIX_PAUSE_STATUSES } from "@/lib/generated/constants"
import { codeAgentPauseContinuePath, codeAgentPauseStopPath } from "@/lib/routes"
import { decideCodePause } from "@/pages/agent/lib/chat-updates"
import type { AgentChatCodePause } from "@/types/serializers"

type Choice = "continue" | "stop"

// A code fix from this chat that reached its spending limit, as a card in the thread where the person reads, beside
// the same choice under its step. Continue gives it another budget of the size it paused with, and Stop deletes the
// work saved so far once they confirm it. The server ships who may decide, so the card never decides from a status.
export function CodePauseCard({ pause }: { pause: AgentChatCodePause }) {
  const [ sending, setSending ] = useState<Choice | null>(null)
  const [ confirmingStop, setConfirmingStop ] = useState(false)
  const offered = pause.status === CODE_FIX_PAUSE_STATUSES.OFFERED
  const blocked = pause.decideBlockedReason != null

  function decide(choice: Choice) {
    setSending(choice)
    const path = choice === "continue" ? codeAgentPauseContinuePath(pause.id) : codeAgentPauseStopPath(pause.id)
    decideCodePause(path, { onFinish: doneSending })
  }

  function doneSending() {
    setSending(null)
  }

  function continueFix() {
    decide("continue")
  }

  function askToStop() {
    setConfirmingStop(true)
  }

  function cancelStop() {
    setConfirmingStop(false)
  }

  function stopFix() {
    setConfirmingStop(false)
    decide("stop")
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Paused code fix">
      <div className="flex items-start gap-2">
        <IconPlayerPause aria-hidden className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{pause.question}</h3>
      </div>
      <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">
        The fix in {pause.repository} spent {pause.spent}.
        {pause.savedBranch && ` Its work so far is saved on ${pause.savedBranch}.`}
      </p>
      {offered && (
        <p className="text-[13px] leading-relaxed text-ink-2">
          Continue gives it another {pause.nextBudget} and carries on where it stopped. Stop deletes the work saved so far.
        </p>
      )}
      {offered && (
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="primary" disabled={blocked || sending !== null} onClick={continueFix}>
            {sending === "continue" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Continue
          </Button>
          <Button size="sm" variant="secondary" disabled={blocked || sending !== null} onClick={askToStop}>
            {sending === "stop" && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Stop
          </Button>
        </div>
      )}
      {offered && pause.decideBlockedReason && <p className="text-[12.5px] text-ink-3">{pause.decideBlockedReason}</p>}
      {!offered && (
        <p className="text-[12.5px] text-ink-3">
          {pause.decidedBy ?? "Someone"}
          {pause.status === CODE_FIX_PAUSE_STATUSES.CONTINUING
            ? ` chose Continue, so the fix carried on with another ${pause.nextBudget}.`
            : " chose Stop, so the saved work was deleted."}
        </p>
      )}
      <ConfirmDeleteDialog
        open={confirmingStop}
        title="Stop this fix?"
        description="The work saved so far is deleted."
        confirmLabel="Stop"
        onConfirm={stopFix}
        onCancel={cancelStop}
      />
    </section>
  )
}

export function CodePauses({ pauses }: { pauses: AgentChatCodePause[] | undefined }) {
  return pauses?.map((pause) => <CodePauseCard key={pause.id} pause={pause} />)
}
