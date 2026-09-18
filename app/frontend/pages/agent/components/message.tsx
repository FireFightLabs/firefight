import { AgentSteps } from "@/pages/agent/components/agent-steps"
import type { ChatTurn } from "@/pages/agent/lib/group-turns"

interface MessageProps {
  turn: ChatTurn
}

// As in ChatGPT, the person's words sit in a bubble on the right and the answer is plain text across
// the column, so the answer reads as the page rather than as a card on it.
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
        <p key={index} className="whitespace-pre-wrap text-[14px] leading-7 text-ink">
          {body}
        </p>
      ))}
    </div>
  )
}
