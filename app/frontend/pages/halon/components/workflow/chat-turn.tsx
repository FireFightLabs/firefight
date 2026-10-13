import { AgentSteps } from "@/components/agent-chat/agent-steps"
import { AnswerSources } from "@/components/agent-chat/answer-sources"
import { AnswerText } from "@/components/agent-chat/answer-text"
import { PersonBubble } from "@/components/agent-chat/person-bubble"
import { type ChatTurn as Turn, TURN_KINDS } from "@/lib/agent-chat/types"
import { CHAT_VISIT } from "@/pages/halon/hooks/use-workflow-edits"

interface ChatTurnProps {
  turn: Turn
  live?: boolean
  fullChatUrl: string | null
  onOpenImage: (attachmentId: string) => void
}

// One turn of the chat beside the canvas: what the person said, or Halon's steps and answer. A card Halon drew, such as
// a chart, is drawn in the full chat, which the turn points to.
export function ChatTurn({ turn, live = false, fullChatUrl, onOpenImage }: ChatTurnProps) {
  if (turn.kind === TURN_KINDS.PERSON) {
    return <PersonBubble body={turn.body} attachments={turn.attachments} onOpenImage={onOpenImage} />
  }

  const drewCards = turn.steps.some((step) => step.card !== null)

  return (
    <div className="flex min-w-0 flex-col gap-3">
      {turn.steps.length > 0 && <AgentSteps steps={turn.steps} thinking={live && turn.bodies.length === 0} reloads={CHAT_VISIT.only} />}
      {turn.bodies.map((body) => (
        <AnswerText key={body.id} text={body.text} />
      ))}
      {!live && turn.sources.length > 0 && <AnswerSources sources={turn.sources} />}
      {!live && drewCards && fullChatUrl && (
        <a href={fullChatUrl} className="text-[12px] text-ink-3 underline-offset-2 hover:underline">
          Halon showed more here. Open the full chat to see it.
        </a>
      )}
    </div>
  )
}
