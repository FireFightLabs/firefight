import { CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import type { AgentStep } from "@/pages/agent/components/agent-steps"
import type { AgentChatMessage } from "@/types/serializers"

export type ChatTurn =
  | { kind: "person"; id: string; body: string; at: string }
  | { kind: "agent"; id: string; steps: AgentStep[]; bodies: string[]; at?: string }

// The agent's side of one answer is saved as several messages, one per tool call and one for the
// reply. A reader sees one answer, so a run of them is drawn as one, and a run with nothing in it,
// such as the agent only looking for tools, is not drawn at all.
export function groupedTurns(messages: AgentChatMessage[]): ChatTurn[] {
  const turns: ChatTurn[] = []

  messages.forEach((message) => {
    if (message.role === CHAT_MESSAGE_ROLES.USER) {
      turns.push({ kind: "person", id: message.id, body: message.body, at: message.at })
      return
    }

    const previous = turns[turns.length - 1]
    const body = message.body.trim()
    if (previous?.kind === "agent") {
      previous.steps.push(...message.tools)
      if (body.length > 0) {
        previous.bodies.push(message.body)
      }
      previous.at = message.at
      return
    }

    turns.push({
      kind: "agent",
      id: message.id,
      steps: [ ...message.tools ],
      bodies: body.length > 0 ? [ message.body ] : [],
      at: message.at,
    })
  })

  return turns.filter((turn) => turn.kind === "person" || turn.steps.length > 0 || turn.bodies.length > 0)
}
