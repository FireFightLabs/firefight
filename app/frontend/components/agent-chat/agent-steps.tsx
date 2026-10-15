import ThinkingState, { type ThinkingRow, type ThinkingRowStatus } from "@/components/agent-ui/thinking-state"
import { CodeFixWorkView } from "@/components/code-fix-work"
import { AGENT_CARD_KINDS, AGENT_STEP_KINDS } from "@/lib/generated/constants"
import { useSettledSteps } from "@/hooks/use-settled-steps"
import { rowStatus } from "@/lib/agent-chat/step-rows"
import { holdsRunOpen, runSummary, type WorkRun, workRuns, workSummary } from "@/lib/agent-chat/work-parts"
import { AnswerText } from "@/components/agent-chat/answer-text"
import { withoutMarkers } from "@/lib/agent-chat/chart-markers"
import { HelperRuns } from "@/components/agent-chat/helper-runs"
import { StepActivity } from "@/components/agent-chat/step-activity"
import { StepOutcomeDetails } from "@/components/agent-chat/step-outcome"
import { type AgentStep, PIECE_KINDS, type TurnPiece } from "@/lib/agent-chat/types"

interface AgentStepsProps {
  // The steps and the status lines Halon wrote between them, in the order they happened.
  pieces: TurnPiece[]
  // Halon is still on this work, so the trace stays open, and each run of steps it finished folds into one line.
  underWay?: boolean
  // What a coding agent's question or pause reloads on the page showing the chat.
  reloads: string[]
}

// A stretch of Halon's work is one trace, every step and status line in the order it happened, so reading something and
// acting on it never split the thread into alternating blocks. Once the work is done it folds into one line that opens
// to the whole story. A step that failed or waits on the person holds the trace open, since it needs a look. A step
// whose provider found nothing answered its check, so it does not.
export function AgentSteps({ pieces, underWay = false, reloads }: AgentStepsProps) {
  const settled = useSettledSteps(stepsIn(pieces))
  const shown = withSettled(pieces, settled)
  const steps = stepsIn(shown)
  // Words with no step around them are only status lines, with no trace to fold them into.
  if (steps.length === 0) {
    const notes = shown.flatMap((piece) => (piece.kind === PIECE_KINDS.TEXT ? [ piece ] : []))
    return <div className="flex flex-col gap-1">{notes.map((note) => <StatusLine key={note.id} text={note.text} />)}</div>
  }

  const runs = workRuns(shown)
  const rows = underWay ? runs.flatMap((run, index) => runRows(run, index === runs.length - 1, reloads)) : shown.map((piece) => pieceRow(piece, reloads))
  const statuses = steps.map((step) => rowStatus(step.status))
  const working = statuses.includes("running")
  const looked = statuses.some((status) => HOLDS_OPEN.includes(status))

  return <ThinkingState rows={rows} active="Working" done={workSummary(steps)} working={working} open={underWay || looked} />
}

const HOLDS_OPEN: ThinkingRowStatus[] = [ "failed", "waiting" ]

function StatusLine({ text }: { text: string }) {
  return <AnswerText text={withoutMarkers(text)} status />
}

// A finished run of more than one step folds into a line saying what it did. The run still going, and one that needs a
// look, stay open.
function runRows(run: WorkRun, last: boolean, reloads: string[]): ThinkingRow[] {
  if (run.kind === PIECE_KINDS.TEXT) {
    return [ pieceRow(run, reloads) ]
  }
  const rows = run.steps.map((step) => stepRow(step, reloads))
  if (last || run.steps.length < 2 || run.steps.some(holdsRunOpen)) {
    return rows
  }

  return [ { id: run.id, primary: runSummary(run.steps), status: "done", rows } ]
}

function pieceRow(piece: TurnPiece, reloads: string[]): ThinkingRow {
  if (piece.kind === PIECE_KINDS.TEXT) {
    return { id: piece.id, primary: "", note: <StatusLine text={piece.text} /> }
  }
  return stepRow(piece.step, reloads)
}

function stepRow(step: AgentStep, reloads: string[]): ThinkingRow {
  const status = rowStatus(step.status)
  return {
    id: step.key,
    primary: step.title,
    secondary: step.headline || undefined,
    status,
    details: step.asked.map(([ label, meta ]) => ({ label, meta })),
    outcome: step.outcome ? <StepOutcomeDetails outcome={step.outcome} /> : undefined,
    quiet: step.kind === AGENT_STEP_KINDS.ROOM,
    live: liveWork(step, status, reloads),
  }
}

function stepsIn(pieces: TurnPiece[]): AgentStep[] {
  return pieces.flatMap((piece) => (piece.kind === PIECE_KINDS.STEP ? [ piece.step ] : []))
}

// Each step as the pace of the trace shows it, still running for a moment after a quick tool answered.
function withSettled(pieces: TurnPiece[], settled: AgentStep[]): TurnPiece[] {
  return pieces.map((piece) => (piece.kind === PIECE_KINDS.STEP ? { ...piece, step: settled.find((step) => step.key === piece.step.key) ?? piece.step } : piece))
}

// What a long step is doing as it goes, under the step that runs it. Helpers and a coding agent show their own work, and
// any other tool shows the last thing it said about how far it got while it runs.
function liveWork(step: AgentStep, status: ThinkingRow["status"], reloads: string[]) {
  const activity = status === "running" && step.activity ? <StepActivity activity={step.activity} /> : undefined
  if (step.card?.kind === AGENT_CARD_KINDS.HELPERS) {
    return (
      <div className="flex min-w-0 flex-col gap-2">
        {activity}
        <HelperRuns toolCallKey={step.key} />
      </div>
    )
  }
  if (!step.progress) {
    return activity
  }

  return (
    <CodeFixWorkView
      work={step.progress}
      running={status === "running"}
      questionBlockedReason={step.questionBlockedReason}
      questionChangeBlockedReason={step.questionChangeBlockedReason}
      pauseBlockedReason={step.pauseBlockedReason}
      reloads={reloads}
    />
  )
}
