import { formatTime } from "@/lib/formatters"
import { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { type AgentStep, type AgentStream, type ChatTurn, TURN_KINDS } from "@/pages/agent/types"
import type { AgentChatMessage, ChatCompaction } from "@/types/serializers"

const LIVE_TURN_ID = "live"

// A time Halon made room, drawn in the trace as a finished step of its own kind with when it happened.
export function roomStep(compaction: ChatCompaction): AgentStep {
  return {
    key: compaction.key,
    title: compaction.title,
    headline: formatTime(compaction.at),
    asked: [],
    status: AGENT_STEP_STATUSES.DONE,
    kind: AGENT_STEP_KINDS.ROOM,
    seconds: 0,
    card: null,
  }
}

// One answer is saved as several messages, one per tool call, so a run of them is drawn as one. Room is made just
// before the model writes, so each time lands in the trace ahead of the reply written after it.
export function groupedTurns(messages: AgentChatMessage[], compactions: ChatCompaction[] = []): ChatTurn[] {
  const turns: ChatTurn[] = []
  const unplaced = [ ...compactions ].sort((first, second) => Date.parse(first.at) - Date.parse(second.at))

  function roomMadeBefore(message: AgentChatMessage): AgentStep[] {
    const made: AgentStep[] = []
    while (unplaced.length > 0 && Date.parse(unplaced[0].at) <= Date.parse(message.createdAt)) {
      const compaction = unplaced.shift()
      if (compaction) {
        made.push(roomStep(compaction))
      }
    }
    return made
  }

  messages.forEach((message) => {
    if (message.role === CHAT_MESSAGE_ROLES.USER) {
      turns.push({ kind: TURN_KINDS.PERSON, id: message.id, body: message.body, attachments: message.attachments })
      return
    }

    const previous = turns[turns.length - 1]
    const steps = [ ...roomMadeBefore(message), ...message.tools ]
    const bodies = message.body.trim().length > 0 ? [ { id: message.id, text: message.body } ] : []
    if (previous?.kind === TURN_KINDS.AGENT) {
      previous.steps.push(...steps)
      previous.bodies.push(...bodies)
      return
    }

    turns.push({ kind: TURN_KINDS.AGENT, id: message.id, steps, bodies })
  })

  // Room made after the last reply belongs to the turn still being written. When a question comes last, that turn is
  // drawn live from the stream instead.
  const madeSince = unplaced.map(roomStep)
  const last = turns[turns.length - 1]
  if (madeSince.length > 0 && last?.kind === TURN_KINDS.AGENT) {
    last.steps.push(...madeSince)
  } else if (madeSince.length > 0 && turns.length === 0) {
    turns.push({ kind: TURN_KINDS.AGENT, id: madeSince[0].key, steps: madeSince, bodies: [] })
  }

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
export function liveTurn(stream: AgentStream, messages: AgentChatMessage[], compactions: ChatCompaction[] = []): ChatTurn | null {
  if (!stream.owed) {
    return null
  }

  const asked = messages[lastQuestionIndex(messages)]
  const madeSinceAsked = asked ? compactions.filter((compaction) => Date.parse(compaction.at) > Date.parse(asked.createdAt)) : compactions
  const saved = groupedTurns(messages.slice(lastQuestionIndex(messages) + 1), madeSinceAsked)[0]
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

// Something placed in the chat by when it happened rather than by a message, such as a held call once it was decided.
export interface Placed {
  at: string
}

export const BEFORE_ALL_TURNS = "start"

// Each placed thing goes after the last turn that started before it, keyed by that turn's id, or before every turn.
export function placeAfterTurns<T extends Placed>(turns: ChatTurn[], messages: AgentChatMessage[], placed: T[]): Map<string, T[]> {
  const startedAt = new Map(messages.map((message) => [ message.id, Date.parse(message.createdAt) ]))
  const starts = turns.flatMap((turn) => {
    const at = startedAt.get(turn.id)
    return at === undefined ? [] : [ { id: turn.id, at } ]
  })
  const placedAfter = new Map<string, T[]>()
  placed.forEach((item) => {
    const at = Date.parse(item.at)
    const after = starts.filter((start) => start.at <= at).pop()?.id ?? BEFORE_ALL_TURNS
    placedAfter.set(after, [ ...(placedAfter.get(after) ?? []), item ])
  })
  return placedAfter
}
