import { duration, stepsWord } from "@/lib/code-fix-work"
import { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_TEXT_ROLES } from "@/lib/generated/constants"
import { type AgentStep, PIECE_KINDS, type TurnPiece, type TurnText } from "@/lib/agent-chat/types"

// A turn as it is drawn, Halon's work (its steps and the status lines written between them) and what it said to the
// person (a question or the turn's result), each where it happened. Page only, the server keeps messages.
export const PART_KINDS = { WORK: "work", SAID: "said" } as const

export type TurnPart =
  | { kind: typeof PART_KINDS.WORK; id: string; pieces: TurnPiece[] }
  | { kind: typeof PART_KINDS.SAID; text: TurnText }

export function turnParts(pieces: TurnPiece[]): TurnPart[] {
  return pieces.reduce<TurnPart[]>((parts, piece) => {
    if (piece.kind === PIECE_KINDS.TEXT && piece.role !== AGENT_TEXT_ROLES.STATUS) {
      return [ ...parts, { kind: PART_KINDS.SAID, text: piece } ]
    }
    const last = parts[parts.length - 1]
    if (last?.kind === PART_KINDS.WORK) {
      return [ ...parts.slice(0, -1), { ...last, pieces: [ ...last.pieces, piece ] } ]
    }
    return [ ...parts, { kind: PART_KINDS.WORK, id: pieceId(piece), pieces: [ piece ] } ]
  }, [])
}

// The work still under way in a live turn is its last, unless Halon asked the person something since.
export function workUnderWay(parts: TurnPart[]): string | null {
  const lastWork = parts.map((part) => part.kind).lastIndexOf(PART_KINDS.WORK)
  const askedSince = parts.slice(lastWork + 1).some((part) => part.kind === PART_KINDS.SAID && part.text.role === AGENT_TEXT_ROLES.QUESTION)
  const part = parts[lastWork]
  return part?.kind === PART_KINDS.WORK && !askedSince ? part.id : null
}

// The steps between two status lines, or around one, which a live turn folds into a line once they are done.
export type WorkRun = { kind: typeof PIECE_KINDS.STEP; id: string; steps: AgentStep[] } | TurnText

export function workRuns(pieces: TurnPiece[]): WorkRun[] {
  return pieces.reduce<WorkRun[]>((runs, piece) => {
    if (piece.kind === PIECE_KINDS.TEXT) {
      return [ ...runs, piece ]
    }
    const last = runs[runs.length - 1]
    if (last?.kind === PIECE_KINDS.STEP) {
      return [ ...runs.slice(0, -1), { ...last, steps: [ ...last.steps, piece.step ] } ]
    }
    return [ ...runs, { kind: PIECE_KINDS.STEP, id: `run:${piece.step.key}`, steps: [ piece.step ] } ]
  }, [])
}

// A step that is still going, failed or waits on the person needs a look, so the run holding it stays open.
export function holdsRunOpen(step: AgentStep): boolean {
  return HOLD_RUN_OPEN.includes(step.status)
}

const HOLD_RUN_OPEN: string[] = [ AGENT_STEP_STATUSES.RUNNING, AGENT_STEP_STATUSES.FAILED, AGENT_STEP_STATUSES.WAITING ]

// "Looked at 12 things · GitHub", "Looked at 3 things, made 1 change · GitHub, Linear". Never "Read", which is how the
// sources list under the result starts.
export function runSummary(steps: AgentStep[]): string {
  const reads = steps.filter((step) => step.kind === AGENT_STEP_KINDS.READ).length
  const changes = steps.filter((step) => step.kind === AGENT_STEP_KINDS.ACT).length
  const read = reads > 0 ? `Looked at ${countOf(reads, "thing")}` : null
  const made = changes > 0 ? `${read ? "made" : "Made"} ${countOf(changes, "change")}` : null
  const did = [ read, made ].filter((words) => words !== null).join(", ")
  const sources = steps.flatMap((step) => (step.source ? [ step.source ] : [])).filter((source, index, all) => all.indexOf(source) === index)
  return sources.length > 0 ? `${did} · ${sources.join(", ")}` : did
}

// "Worked for 5m 36s · 34 steps", counting only steps Halon took, not the times it made room.
export function workSummary(steps: AgentStep[]): string {
  const seconds = steps.reduce((total, step) => total + step.seconds, 0)
  const taken = stepsWord(steps.filter((step) => step.kind !== AGENT_STEP_KINDS.ROOM).length)
  return seconds < 1 ? `Worked for a moment · ${taken}` : `Worked for ${duration(seconds)} · ${taken}`
}

function countOf(count: number, noun: string): string {
  return count === 1 ? `1 ${noun}` : `${count} ${noun}s`
}

function pieceId(piece: TurnPiece): string {
  return piece.kind === PIECE_KINDS.STEP ? piece.step.key : piece.id
}
