import { AgentCard } from "@/pages/agent/components/agent-card"
import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { AnswerText } from "@/pages/agent/components/answer-text"
import { PersonBubble } from "@/pages/agent/components/person-bubble"
import { type ChatTurn, TURN_KINDS } from "@/pages/agent/types"

interface MessageProps {
  turn: ChatTurn
  live?: boolean
  onOpenImage: (attachmentId: string) => void
}

export function Message({ turn, live = false, onOpenImage }: MessageProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return <PersonBubble body={turn.body} attachments={turn.attachments} onOpenImage={onOpenImage} />
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
