import ThinkingState, { type ThinkingRow } from "@/components/agent-ui/thinking-state"
import { CodeFixWorkView } from "@/components/code-fix-work"
import { stepsWord } from "@/lib/code-fix-work"
import { AGENT_CARD_KINDS, AGENT_STEP_KINDS } from "@/lib/generated/constants"
import { useSettledSteps } from "@/hooks/use-settled-steps"
import { rowStatus } from "@/lib/agent-chat/step-rows"
import { HelperRuns } from "@/components/agent-chat/helper-runs"
import { StepActivity } from "@/components/agent-chat/step-activity"
import { StepOutcomeDetails } from "@/components/agent-chat/step-outcome"
import type { AgentStep } from "@/lib/agent-chat/types"

interface AgentStepsProps {
  steps: AgentStep[]
  // The agent is still on this turn and has not started its answer, so the trace stays open between steps.
  thinking?: boolean
  // What a coding agent's question or pause reloads on the page showing the chat.
  reloads: string[]
}

// A turn's work is one trace, every step in the order it ran, so reading something and acting on it never split the
// thread into alternating blocks. A step that failed or waits on the person holds the trace open, since it needs a look.
// A step whose provider found nothing answered its check, so it does not.
export function AgentSteps({ steps, thinking = false, reloads }: AgentStepsProps) {
  const settled = useSettledSteps(steps)
  const rows = settled.map((step) => toRow(step, reloads))
  const working = rows.some((row) => row.status === "running")
  const needsLook = rows.some((row) => row.status === "failed" || row.status === "waiting")
  const seconds = settled.reduce((total, step) => total + step.seconds, 0)
  const taken = settled.filter((step) => step.kind !== AGENT_STEP_KINDS.ROOM).length

  return (
    <ThinkingState
      rows={rows}
      active="Working"
      done={summary(seconds, taken)}
      working={working}
      open={thinking || needsLook}
    />
  )
}

function toRow(step: AgentStep, reloads: string[]): ThinkingRow {
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

function summary(seconds: number, count: number) {
  const steps = stepsWord(count)
  if (seconds < 1) {
    return `Worked for a moment · ${steps}`
  }
  if (seconds === 1) {
    return `Worked for 1 second · ${steps}`
  }

  return `Worked for ${seconds} seconds · ${steps}`
}
