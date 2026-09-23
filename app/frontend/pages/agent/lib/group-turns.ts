import { CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { type AgentStep, type AgentStream, type ChatTurn, TURN_KINDS } from "@/pages/agent/types"
import type { AgentChatMessage } from "@/types/serializers"

const LIVE_TURN_ID = "live"

// One answer is saved as several messages, one per tool call, so a run of them is drawn as one.
export function groupedTurns(messages: AgentChatMessage[]): ChatTurn[] {
  const turns: ChatTurn[] = []

  messages.forEach((message) => {
    if (message.role === CHAT_MESSAGE_ROLES.USER) {
      turns.push({ kind: TURN_KINDS.PERSON, id: message.id, body: message.body })
      return
    }

    const previous = turns[turns.length - 1]
    const bodies = message.body.trim().length > 0 ? [ { id: message.id, text: message.body } ] : []
    if (previous?.kind === TURN_KINDS.AGENT) {
      previous.steps.push(...message.tools)
      previous.bodies.push(...bodies)
      return
    }

    turns.push({ kind: TURN_KINDS.AGENT, id: message.id, steps: [ ...message.tools ], bodies })
  })

  return turns.filter((turn) => turn.kind === TURN_KINDS.PERSON || turn.steps.length > 0 || turn.bodies.length > 0)
}

// While an answer is owed, whatever is saved after the last question is the turn in progress, and it is drawn live
// rather than as a finished reply.
export function settledMessages(messages: AgentChatMessage[], owed: boolean): AgentChatMessage[] {
  if (!owed) {
    return messages
  }

  return messages.slice(0, lastQuestionIndex(messages) + 1)
}

// The turn in progress: what the socket has sent, on top of what was already saved when the page loaded.
export function liveTurn(stream: AgentStream, messages: AgentChatMessage[]): ChatTurn | null {
  if (!stream.owed) {
    return null
  }

  const saved = groupedTurns(messages.slice(lastQuestionIndex(messages) + 1))[0]
  const savedSteps = saved?.kind === TURN_KINDS.AGENT ? saved.steps : []
  const savedBodies = saved?.kind === TURN_KINDS.AGENT ? saved.bodies : []
  const steps = mergeSteps(savedSteps, stream.steps)
  const bodies = stream.text.length > 0 ? [ { id: LIVE_TURN_ID, text: stream.text } ] : savedBodies
  if (steps.length === 0 && bodies.length === 0) {
    return null
  }

  return { kind: TURN_KINDS.AGENT, id: LIVE_TURN_ID, steps, bodies }
}

function lastQuestionIndex(messages: AgentChatMessage[]): number {
  return messages.map((message) => message.role).lastIndexOf(CHAT_MESSAGE_ROLES.USER)
}

// A step the socket reported is newer than its saved copy, so it wins.
function mergeSteps(saved: AgentStep[], live: AgentStep[]): AgentStep[] {
  const merged = saved.map((step) => live.find((candidate) => candidate.key === step.key) ?? step)
  const unseen = live.filter((step) => !saved.some((candidate) => candidate.key === step.key))
  return [ ...merged, ...unseen ]
}
