import { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS, AGENT_TEXT_ROLES } from "@/lib/generated/constants"
import type { CodeFixWork } from "@/lib/code-fix-work"
import type { StepOutcome } from "@/lib/step-outcome"
import { roomStep } from "@/lib/agent-chat/group-turns"
import { type AgentCard, type AgentStep, PIECE_KINDS, type StepKind, type StepStatus, type StreamEventType, type ToolActivity, type TurnPiece } from "@/lib/agent-chat/types"

export interface StreamEvent {
  type: StreamEventType
  seq?: number
  text?: string
  key?: string
  title?: string
  headline?: string
  asked?: [ string, string ][]
  status?: StepStatus
  kind?: StepKind
  source?: string | null
  seconds?: number
  card?: AgentCard | null
  outcome?: StepOutcome | null
  progress?: CodeFixWork | null
  activity?: ToolActivity | null
  at?: string
}

interface Placed<T> {
  item: T
  // When it first appeared, which decides where it sits.
  first: number
  // The latest event that changed it, so an older one arriving late never undoes it.
  last: number
}

// What a turn has streamed so far. Action Cable hands broadcasts to a pool of threads, so they can arrive out of order.
// Every event carries when it was sent, and each piece is placed by that rather than by when it arrived.
export interface Streamed {
  since: number
  chunks: Placed<string>[]
  steps: Placed<AgentStep>[]
}

export const NOTHING_STREAMED: Streamed = { since: 0, chunks: [], steps: [] }

export function streamedText(streamed: Streamed): string {
  return streamed.chunks.map((chunk) => chunk.item).join("")
}

export function streamedSteps(streamed: Streamed): AgentStep[] {
  return streamed.steps.map((step) => step.item)
}

// Words and steps in the order they were sent, the words between two steps as one piece. Words count as the turn's
// result until a step follows them, which the turn's grouping settles (settledRoles).
export function streamedPieces(streamed: Streamed): TurnPiece[] {
  const sent = [
    ...streamed.chunks.map((chunk) => ({ first: chunk.first, text: chunk.item, step: null })),
    ...streamed.steps.map((step) => ({ first: step.first, text: null, step: step.item })),
  ].sort((one, other) => one.first - other.first)

  return sent.reduce<TurnPiece[]>((pieces, entry) => {
    if (entry.step) {
      return [ ...pieces, { kind: PIECE_KINDS.STEP, step: entry.step } ]
    }
    const last = pieces[pieces.length - 1]
    if (last?.kind === PIECE_KINDS.TEXT) {
      return [ ...pieces.slice(0, -1), { ...last, text: last.text + (entry.text ?? "") } ]
    }
    return [ ...pieces, { kind: PIECE_KINDS.TEXT, id: `${STREAMED_TEXT}${entry.first}`, text: entry.text ?? "", role: AGENT_TEXT_ROLES.RESULT } ]
  }, [])
}

const STREAMED_TEXT = "streamed-"

// A turn starting drops only what was sent before it, so a late start never wipes the steps that followed it.
export function withEvent(streamed: Streamed, event: StreamEvent): Streamed {
  const seq = event.seq ?? 0
  if (event.type === AGENT_STREAM_EVENTS.THINKING) {
    if (seq < streamed.since) {
      return streamed
    }
    return {
      since: seq,
      chunks: streamed.chunks.filter((chunk) => chunk.first > seq),
      steps: streamed.steps.filter((step) => step.first > seq),
    }
  }
  if (seq < streamed.since) {
    return streamed
  }
  if (event.type === AGENT_STREAM_EVENTS.CHUNK) {
    return { ...streamed, chunks: placed(streamed.chunks, { item: event.text ?? "", first: seq, last: seq }) }
  }
  if (event.type === AGENT_STREAM_EVENTS.STEP) {
    return { ...streamed, steps: withStep(streamed.steps, stepOf(event), seq) }
  }
  if (event.type === AGENT_STREAM_EVENTS.MADE_ROOM || event.type === AGENT_STREAM_EVENTS.SWITCHED_MODEL) {
    const key = event.key ?? ""
    if (streamed.steps.some((step) => step.item.key === key)) {
      return streamed
    }
    const line = roomStep({ key, title: event.title ?? "", at: event.at ?? new Date().toISOString() })
    return { ...streamed, steps: placed(streamed.steps, { item: line, first: seq, last: seq }) }
  }
  return streamed
}

function stepOf(event: StreamEvent): AgentStep {
  return {
    key: event.key ?? "",
    title: event.title ?? "",
    headline: event.headline ?? "",
    asked: event.asked ?? [],
    status: event.status ?? AGENT_STEP_STATUSES.RUNNING,
    kind: event.kind ?? AGENT_STEP_KINDS.ACT,
    source: event.source ?? null,
    seconds: event.seconds ?? 0,
    card: event.card ?? null,
    outcome: event.outcome ?? null,
    progress: event.progress ?? null,
    activity: event.activity ?? null,
    questionBlockedReason: null,
    questionChangeBlockedReason: null,
    pauseBlockedReason: null,
  }
}

function withStep(steps: Placed<AgentStep>[], step: AgentStep, seq: number): Placed<AgentStep>[] {
  const already = steps.find((candidate) => candidate.item.key === step.key)
  if (!already) {
    return placed(steps, { item: step, first: seq, last: seq })
  }

  const moved = {
    item: seq >= already.last ? { ...already.item, ...step } : already.item,
    first: Math.min(already.first, seq),
    last: Math.max(already.last, seq),
  }
  return placed(steps.filter((candidate) => candidate !== already), moved)
}

function placed<T>(list: Placed<T>[], entry: Placed<T>): Placed<T>[] {
  return [ ...list, entry ].sort((one, other) => one.first - other.first)
}
