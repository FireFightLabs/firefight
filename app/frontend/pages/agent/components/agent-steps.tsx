import ThinkingState, { type ThinkingRow } from "@/components/agent-ui/thinking-state"
import { CodeFixWorkView } from "@/components/code-fix-work"
import { stepsWord } from "@/lib/code-fix-work"
import { AGENT_CARD_KINDS, AGENT_STEP_KINDS } from "@/lib/generated/constants"
import { useSettledSteps } from "@/pages/agent/hooks/use-settled-steps"
import { CODE_AGENT_RELOADS } from "@/pages/agent/lib/chat-updates"
import { rowStatus } from "@/pages/agent/lib/step-rows"
import { HelperRuns } from "@/pages/agent/components/helper-runs"
import { StepOutcomeDetails } from "@/pages/agent/components/step-outcome"
import type { AgentStep } from "@/pages/agent/types"

interface AgentStepsProps {
  steps: AgentStep[]
  // The agent is still on this turn and has not started its answer, so the trace stays open between steps.
  thinking?: boolean
}

// A turn's work is one trace, every step in the order it ran, so reading something and acting on it never split the
// thread into alternating blocks. A step that failed or waits on the person holds the trace open, since it needs a look.
// A step whose provider found nothing answered its check, so it does not.
export function AgentSteps({ steps, thinking = false }: AgentStepsProps) {
  const settled = useSettledSteps(steps)
  const rows = settled.map(toRow)
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

function toRow(step: AgentStep): ThinkingRow {
  const status = rowStatus(step.status)
  return {
    id: step.key,
    primary: step.title,
    secondary: step.headline || undefined,
    status,
    details: step.asked.map(([ label, meta ]) => ({ label, meta })),
    outcome: step.outcome ? <StepOutcomeDetails outcome={step.outcome} /> : undefined,
    quiet: step.kind === AGENT_STEP_KINDS.ROOM,
    live: step.card?.kind === AGENT_CARD_KINDS.HELPERS
      ? <HelperRuns toolCallKey={step.key} />
      : liveWork(step, status),
  }
}

// A coding agent's work as it goes, under the step that runs it.
function liveWork(step: AgentStep, status: ThinkingRow["status"]) {
  if (!step.progress) {
    return undefined
  }

  return (
    <CodeFixWorkView
      work={step.progress}
      running={status === "running"}
      questionBlockedReason={step.questionBlockedReason}
      questionChangeBlockedReason={step.questionChangeBlockedReason}
      pauseBlockedReason={step.pauseBlockedReason}
      reloads={CODE_AGENT_RELOADS}
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
