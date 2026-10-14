import { withNewerQuestion } from "@/lib/code-fix-work"
import { formatTime } from "@/lib/formatters"
import { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_TEXT_ROLES, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { type AgentStep, type AgentStream, type ChatTurn, PIECE_KINDS, type TextRole, TURN_KINDS, type TurnPiece } from "@/lib/agent-chat/types"
import type { AgentChatMessage, ChatCompaction } from "@/types/serializers"

const LIVE_TURN_ID = "live"

// A time Halon made room, or carried on with a backup model, drawn in the trace as a finished quiet step with when it
// happened.
export function roomStep(compaction: ChatCompaction): AgentStep {
  return {
    key: compaction.key,
    title: compaction.title,
    headline: formatTime(compaction.at),
    asked: [],
    status: AGENT_STEP_STATUSES.DONE,
    kind: AGENT_STEP_KINDS.ROOM,
    source: null,
    seconds: 0,
    card: null,
    outcome: null,
    progress: null,
    questionBlockedReason: null,
    questionChangeBlockedReason: null,
    pauseBlockedReason: null,
  }
}

// One answer is saved as several messages, one per tool call, so a run of them is drawn as one, in the order it
// happened. Each message's words come before the calls it made. Room is made just before the model writes, so each time
// lands in the trace ahead of the words written after it.
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
    const words = message.body.trim().length > 0 ? [ textPiece(message.id, message.body, roleOf(message.saidAs)) ] : []
    const pieces = [ ...roomMadeBefore(message).map(stepPiece), ...words, ...message.tools.map(stepPiece) ]
    const models = message.model ? [ message.model ] : []
    if (previous?.kind === TURN_KINDS.AGENT) {
      previous.pieces.push(...pieces)
      previous.models = withoutRepeats([ ...previous.models, ...models ])
      // The reply that ends the turn lists everything the turn read, so it replaces what an earlier reply listed.
      previous.sources = message.sources.length > 0 ? message.sources : previous.sources
      return
    }

    turns.push({ kind: TURN_KINDS.AGENT, id: message.id, pieces, models, sources: message.sources })
  })

  // Room made after the last reply belongs to the turn still being written. When a question comes last, that turn is
  // drawn live from the stream instead.
  const madeSince = unplaced.map((compaction) => stepPiece(roomStep(compaction)))
  const last = turns[turns.length - 1]
  if (madeSince.length > 0 && last?.kind === TURN_KINDS.AGENT) {
    last.pieces.push(...madeSince)
  } else if (madeSince.length > 0 && turns.length === 0) {
    turns.push({ kind: TURN_KINDS.AGENT, id: unplaced[0].key, pieces: madeSince, models: [], sources: [] })
  }

  return turns
    .filter((turn) => turn.kind === TURN_KINDS.PERSON || turn.pieces.length > 0)
    .map((turn) => (turn.kind === TURN_KINDS.AGENT ? { ...turn, pieces: settledRoles(turn.pieces) } : turn))
}

// While an answer is owed, whatever is saved after the last question is the turn in progress, and it is drawn live
// rather than as a finished reply.
export function settledMessages(messages: AgentChatMessage[], owed: boolean): AgentChatMessage[] {
  if (!owed) {
    return messages
  }

  return messages.slice(0, lastQuestionIndex(messages) + 1)
}

// The turn in progress is what was saved when the page last read the chat, then what the socket sent since. A step the
// socket reported again replaces its saved copy where it stands. Words the socket sent just before a saved step were
// saved with that step's message, so they are not drawn twice.
export function liveTurn(stream: AgentStream, messages: AgentChatMessage[], compactions: ChatCompaction[] = []): ChatTurn | null {
  if (!stream.owed) {
    return null
  }

  const asked = messages[lastQuestionIndex(messages)]
  const madeSinceAsked = asked ? compactions.filter((compaction) => Date.parse(compaction.at) > Date.parse(asked.createdAt)) : compactions
  const saved = groupedTurns(messages.slice(lastQuestionIndex(messages) + 1), madeSinceAsked)[0]
  const savedPieces = saved?.kind === TURN_KINDS.AGENT ? saved.pieces : []
  const savedSteps = stepsOf(savedPieces)
  const savedWords = new Set(savedPieces.flatMap((piece) => (piece.kind === PIECE_KINDS.TEXT ? [ piece.text.trim() ] : [])))
  const merged = mergeSteps(savedSteps, stream.steps)
  const isSaved = (key: string) => savedSteps.some((step) => step.key === key)
  const newer = stream.pieces.filter((piece, index) => {
    if (piece.kind === PIECE_KINDS.STEP) {
      return !isSaved(piece.step.key)
    }
    const next = stream.pieces[index + 1]
    const savedWithNext = next?.kind === PIECE_KINDS.STEP && isSaved(next.step.key)
    return !savedWithNext && piece.text.trim().length > 0 && !savedWords.has(piece.text.trim())
  })
  const latest = (piece: TurnPiece) => (piece.kind === PIECE_KINDS.STEP ? stepPiece(merged.find((step) => step.key === piece.step.key) ?? piece.step) : piece)
  const pieces = settledRoles([ ...savedPieces, ...newer ].map(latest))
  if (pieces.length === 0) {
    return null
  }

  return { kind: TURN_KINDS.AGENT, id: LIVE_TURN_ID, pieces, models: [], sources: [] }
}

// Halon is writing words the socket sent and nothing has followed yet, which read as the turn's result while they come
// in, so the page does not also say it is working under them.
export function writingWords(stream: AgentStream): boolean {
  const last = stream.pieces[stream.pieces.length - 1]
  return last?.kind === PIECE_KINDS.TEXT && last.text.trim().length > 0
}

// Every step of a turn, in the order they ran.
export function stepsOf(pieces: TurnPiece[]): AgentStep[] {
  return pieces.flatMap((piece) => (piece.kind === PIECE_KINDS.STEP ? [ piece.step ] : []))
}

// Words are the turn's result only while nothing follows them. Once Halon calls a tool or writes again in the same turn
// they are a status line among its steps, which is how the server reads a saved turn (Chat::TurnText), so a turn reads
// the same live and reloaded. Words that put a change to the person stay where they were asked.
export function settledRoles(pieces: TurnPiece[]): TurnPiece[] {
  return pieces.map((piece, index) => {
    if (piece.kind !== PIECE_KINDS.TEXT || piece.role !== AGENT_TEXT_ROLES.RESULT) {
      return piece
    }
    const carriedOn = pieces.slice(index + 1).some((later) => later.kind === PIECE_KINDS.TEXT || later.step.kind !== AGENT_STEP_KINDS.ROOM)
    return carriedOn ? { ...piece, role: AGENT_TEXT_ROLES.STATUS } : piece
  })
}

function stepPiece(step: AgentStep): TurnPiece {
  return { kind: PIECE_KINDS.STEP, step }
}

function textPiece(id: string, text: string, role: TextRole): TurnPiece {
  return { kind: PIECE_KINDS.TEXT, id, text, role }
}

// A message saved before its words were read this way says nothing, and reads as the turn's result until something
// follows it.
function roleOf(saidAs: string | null): TextRole {
  return isTextRole(saidAs) ? saidAs : AGENT_TEXT_ROLES.RESULT
}

function isTextRole(value: string | null): value is TextRole {
  return value !== null && Object.values<string>(AGENT_TEXT_ROLES).includes(value)
}

// A turn a model wrote throughout names it once. One handed to another model mid-turn names both, in order.
function withoutRepeats(models: string[]): string[] {
  return models.filter((model, index) => models.indexOf(model) === index)
}

function lastQuestionIndex(messages: AgentChatMessage[]): number {
  return messages.map((message) => message.role).lastIndexOf(CHAT_MESSAGE_ROLES.USER)
}

// A step the socket reported is newer than its saved copy, so it wins, except for who may answer or decide, which only
// the saved copy knows, and a question whose answer changed since the change last reported.
function mergeSteps(saved: AgentStep[], live: AgentStep[]): AgentStep[] {
  const merged = saved.map((step) => {
    const reported = live.find((candidate) => candidate.key === step.key)
    if (!reported) {
      return step
    }
    return {
      ...reported,
      progress: withNewerQuestion(reported.progress, step.progress),
      questionBlockedReason: step.questionBlockedReason,
      questionChangeBlockedReason: step.questionChangeBlockedReason,
      pauseBlockedReason: step.pauseBlockedReason,
    }
  })
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
