import ThinkingState, { type ThinkingRow, type ThinkingRowStatus } from "@/components/agent-ui/thinking-state"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import { useSettledSteps } from "@/pages/agent/hooks/use-settled-steps"
import type { AgentStep, StepStatus } from "@/pages/agent/types"

interface AgentStepsProps {
  steps: AgentStep[]
  // The agent is still on this turn and has not started its answer, so the trace stays open between steps.
  thinking?: boolean
}

const ROW_STATUSES: Record<StepStatus, ThinkingRowStatus> = {
  [AGENT_STEP_STATUSES.RUNNING]: "running",
  [AGENT_STEP_STATUSES.DONE]: "done",
  [AGENT_STEP_STATUSES.FAILED]: "failed",
  [AGENT_STEP_STATUSES.WAITING]: "waiting",
  [AGENT_STEP_STATUSES.CANCELLED]: "cancelled",
}

// A turn's work is one trace, every step in the order it ran, so reading something and acting on it never split the
// thread into alternating blocks. A step that failed or waits on the person holds the trace open, since it needs a look.
export function AgentSteps({ steps, thinking = false }: AgentStepsProps) {
  const settled = useSettledSteps(steps)
  const rows = settled.map(toRow)
  const working = rows.some((row) => row.status === "running")
  const needsLook = rows.some((row) => row.status === "failed" || row.status === "waiting")
  const seconds = settled.reduce((total, step) => total + step.seconds, 0)

  return (
    <ThinkingState
      rows={rows}
      active="Working"
      done={summary(seconds, rows.length)}
      working={working}
      open={thinking || needsLook}
    />
  )
}

function toRow(step: AgentStep): ThinkingRow {
  return {
    id: step.key,
    primary: step.title,
    secondary: step.headline || undefined,
    status: isStepStatus(step.status) ? ROW_STATUSES[step.status] : "running",
    details: step.asked.map(([ label, meta ]) => ({ label, meta })),
  }
}

function summary(seconds: number, count: number) {
  const steps = count === 1 ? "1 step" : `${count} steps`
  if (seconds < 1) {
    return `Worked for a moment · ${steps}`
  }
  if (seconds === 1) {
    return `Worked for 1 second · ${steps}`
  }

  return `Worked for ${seconds} seconds · ${steps}`
}

function isStepStatus(value: string): value is StepStatus {
  return Object.values<string>(AGENT_STEP_STATUSES).includes(value)
}
