import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { AnswerText } from "@/pages/agent/components/answer-text"
import type { ChatTurn } from "@/pages/agent/types"

interface MessageProps {
  turn: ChatTurn
}

export function Message({ turn }: MessageProps) {
  if (turn.kind === "person") {
    return (
      <p className="max-w-[75%] self-end whitespace-pre-wrap rounded-[18px] bg-accent-tint px-4 py-2 text-[14px] leading-relaxed text-ink">
        {turn.body}
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      {turn.steps.length > 0 && <AgentSteps steps={turn.steps} />}
      {turn.bodies.map((body, index) => (
        <AnswerText key={index} text={body} />
      ))}
    </div>
  )
}
