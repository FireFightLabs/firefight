import { AgentSteps } from "@/components/agent-chat/agent-steps"
import { AnswerText } from "@/components/agent-chat/answer-text"
import { PART_KINDS, turnParts, workUnderWay } from "@/lib/agent-chat/work-parts"
import type { TurnPiece } from "@/lib/agent-chat/types"

interface TurnStoryProps {
  pieces: TurnPiece[]
  // The turn is still being written.
  live: boolean
  // What a coding agent's question or pause reloads on the page showing the chat.
  reloads: string[]
}

// Halon's turn in the order it happened. Its work folds once done, and what it said to the person, a question or the
// turn's result, stays where it was said and never folds with it.
export function TurnStory({ pieces, live, reloads }: TurnStoryProps) {
  const parts = turnParts(pieces)
  const underWay = live ? workUnderWay(parts) : null

  return (
    <>
      {parts.map((part) => (part.kind === PART_KINDS.WORK
        ? <AgentSteps key={part.id} pieces={part.pieces} underWay={part.id === underWay} reloads={reloads} />
        : <AnswerText key={part.text.id} text={part.text.text} />))}
    </>
  )
}
