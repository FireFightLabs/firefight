import { AgentCard } from "@/pages/agent/components/agent-card"
import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { AnswerText } from "@/pages/agent/components/answer-text"
import { MessageAttachments } from "@/pages/agent/components/message-attachments"
import { type ChatTurn, TURN_KINDS } from "@/pages/agent/types"

interface MessageProps {
  turn: ChatTurn
  live?: boolean
  onOpenImage: (attachmentId: string) => void
}

export function Message({ turn, live = false, onOpenImage }: MessageProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return (
      <div className="flex flex-col items-end gap-1.5">
        {turn.attachments.length > 0 && <MessageAttachments attachments={turn.attachments} onOpenImage={onOpenImage} />}
        {turn.body.length > 0 && (
          <p className="max-w-[85%] self-end whitespace-pre-wrap rounded-[18px] rounded-br-md border border-border bg-surface-selected px-4 py-2.5 text-[14px] leading-relaxed text-ink [overflow-wrap:anywhere] sm:max-w-[75%]">
            {turn.body}
          </p>
        )}
      </div>
    )
  }

  // The answer reads first and a card follows it, the same order Slack posts them in.
  const cards = turn.steps.filter((step) => step.card !== null)

  return (
    <div className="flex min-w-0 flex-col gap-3">
      {turn.steps.length > 0 && <AgentSteps steps={turn.steps} thinking={live && turn.bodies.length === 0} />}
      {turn.bodies.map((body) => (
        <AnswerText key={body.id} text={body.text} />
      ))}
      {cards.map((step) => step.card && <AgentCard key={step.key} card={step.card} stepKey={step.key} />)}
    </div>
  )
}
