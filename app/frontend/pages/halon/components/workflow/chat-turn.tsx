import { AnswerSources } from "@/components/agent-chat/answer-sources"
import { PersonBubble } from "@/components/agent-chat/person-bubble"
import { TurnStory } from "@/components/agent-chat/turn-story"
import { stepsOf } from "@/lib/agent-chat/group-turns"
import { type ChatTurn as Turn, TURN_KINDS } from "@/lib/agent-chat/types"
import { AGENT_CARD_KINDS } from "@/lib/generated/constants"
import { CHAT_VISIT } from "@/pages/halon/hooks/use-workflow-edits"

// Charts, a helper's among them, are drawn here in the answer (TurnStory).
const CHART_CARDS: string[] = [ AGENT_CARD_KINDS.CHART, AGENT_CARD_KINDS.HELPERS ]

interface ChatTurnProps {
  turn: Turn
  live?: boolean
  fullChatUrl: string | null
  onOpenImage: (attachmentId: string) => void
}

// One turn of the chat beside the canvas: what the person said, or Halon's steps and answer with its charts where it
// placed them. Any other card Halon drew is drawn in the full chat, which the turn points to.
export function ChatTurn({ turn, live = false, fullChatUrl, onOpenImage }: ChatTurnProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return <PersonBubble body={turn.body} attachments={turn.attachments} onOpenImage={onOpenImage} />
  }

  const drewCards = stepsOf(turn.pieces).some((step) => step.card !== null && !CHART_CARDS.includes(step.card.kind))

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <TurnStory pieces={turn.pieces} live={live} reloads={CHAT_VISIT.only} />
      {!live && turn.sources.length > 0 && <AnswerSources sources={turn.sources} />}
      {!live && drewCards && fullChatUrl && (
        <a href={fullChatUrl} className="text-[12px] text-ink-3 underline-offset-2 hover:underline">
          Halon showed more here. Open the full chat to see it.
        </a>
      )}
    </div>
  )
}
