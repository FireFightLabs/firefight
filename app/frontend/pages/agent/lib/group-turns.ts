import { CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import type { AgentStream, ChatTurn } from "@/pages/agent/types"
import type { AgentChatMessage } from "@/types/serializers"

const LIVE_TURN_ID = "live"

// The agent's side of one answer is saved as several messages, one per tool call and one for the
// reply. A reader sees one answer, so a run of them is drawn as one, and a run with nothing in it,
// such as the agent only looking for tools, is not drawn at all.
export function groupedTurns(messages: AgentChatMessage[]): ChatTurn[] {
  const turns: ChatTurn[] = []

  messages.forEach((message) => {
    if (message.role === CHAT_MESSAGE_ROLES.USER) {
      turns.push({ kind: "person", id: message.id, body: message.body })
      return
    }

    const previous = turns[turns.length - 1]
    const bodies = message.body.trim().length > 0 ? [ message.body ] : []
    if (previous?.kind === "agent") {
      previous.steps.push(...message.tools)
      previous.bodies.push(...bodies)
      return
    }

    turns.push({ kind: "agent", id: message.id, steps: [ ...message.tools ], bodies })
  })

  return turns.filter((turn) => turn.kind === "person" || turn.steps.length > 0 || turn.bodies.length > 0)
}

// The answer being written, drawn like a saved one until the saved one replaces it.
export function liveTurn(stream: AgentStream): ChatTurn | null {
  if (stream.steps.length === 0 && stream.text.length === 0) {
    return null
  }

  return { kind: "agent", id: LIVE_TURN_ID, steps: stream.steps, bodies: stream.text.length > 0 ? [ stream.text ] : [] }
}
