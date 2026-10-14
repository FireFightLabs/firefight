import { CODE_AGENT_RELOADS } from "@/pages/agent/lib/chat-updates"
import { AgentCard } from "@/pages/agent/components/agent-card"
import { AnswerSources } from "@/components/agent-chat/answer-sources"
import { PersonBubble } from "@/components/agent-chat/person-bubble"
import { TurnStory } from "@/components/agent-chat/turn-story"
import { stepsOf } from "@/lib/agent-chat/group-turns"
import { type ChatTurn, TURN_KINDS } from "@/pages/agent/types"

interface MessageProps {
  turn: ChatTurn
  live?: boolean
  onOpenImage: (attachmentId: string) => void
}

// Quiet, under the answer, so someone switching models can compare what each wrote.
function AnsweredBy({ models }: { models: string[] }) {
  return <p className="text-[11.5px] leading-4 text-ink-3">{models.join(", then ")}</p>
}

export function Message({ turn, live = false, onOpenImage }: MessageProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return <PersonBubble body={turn.body} attachments={turn.attachments} onOpenImage={onOpenImage} />
  }

  // The answer reads first and a card follows it, the same order Slack posts them in.
  const cards = stepsOf(turn.pieces).filter((step) => step.card !== null)

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <TurnStory pieces={turn.pieces} live={live} reloads={CODE_AGENT_RELOADS} />
      {!live && turn.sources.length > 0 && <AnswerSources sources={turn.sources} />}
      {cards.map((step) => step.card && <AgentCard key={step.key} card={step.card} stepKey={step.key} />)}
      {!live && turn.models.length > 0 && <AnsweredBy models={turn.models} />}
    </div>
  )
}
