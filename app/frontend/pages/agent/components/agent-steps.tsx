import TaskRows from "@/components/agent-ui/task-rows"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import type { AgentStep, StepStatus } from "@/pages/agent/types"

const ROW_STATUS: Record<StepStatus, "done" | "running" | "waiting" | "cancelled"> = {
  [AGENT_STEP_STATUSES.DONE]: "done",
  [AGENT_STEP_STATUSES.RUNNING]: "running",
  [AGENT_STEP_STATUSES.WAITING]: "waiting",
  [AGENT_STEP_STATUSES.CANCELLED]: "cancelled",
}

interface AgentStepsProps {
  steps: AgentStep[]
}

export function AgentSteps({ steps }: AgentStepsProps) {
  const rows = steps.map((step) => ({
    key: step.key,
    label: step.title,
    amount: step.headline,
    status: isStepStatus(step.status) ? ROW_STATUS[step.status] : ("running" as const),
    details: step.asked.map(([ name, value ]) => ({ label: name, meta: value })),
  }))

  return <TaskRows rows={rows} className="w-full" />
}

function isStepStatus(value: string): value is StepStatus {
  return Object.values<string>(AGENT_STEP_STATUSES).includes(value)
}
