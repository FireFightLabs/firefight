import { AgentCard } from "@/pages/agent/components/agent-card"
import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { AnswerText } from "@/pages/agent/components/answer-text"
import { type ChatTurn, TURN_KINDS } from "@/pages/agent/types"

interface MessageProps {
  turn: ChatTurn
}

export function Message({ turn }: MessageProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return (
      <p className="max-w-[75%] self-end whitespace-pre-wrap rounded-[18px] bg-accent-tint px-4 py-2 text-[14px] leading-relaxed text-ink">
        {turn.body}
      </p>
    )
  }

  // The answer reads first and a card follows it, the same order Slack posts them in.
  const cards = turn.steps.filter((step) => step.card !== null)

  return (
    <div className="flex flex-col gap-3">
      {turn.steps.length > 0 && <AgentSteps steps={turn.steps} />}
      {turn.bodies.map((body) => (
        <AnswerText key={body.id} text={body.text} />
      ))}
      {cards.map((step) => step.card && <AgentCard key={step.key} card={step.card} />)}
    </div>
  )
}
