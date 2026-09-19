import TaskRows from "@/components/agent-ui/task-rows"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import type { AgentStep } from "@/pages/agent/types"

interface AgentStepsProps {
  steps: AgentStep[]
}

export function AgentSteps({ steps }: AgentStepsProps) {
  const rows = steps.map((step) => ({
    key: step.key,
    label: step.title,
    amount: step.headline,
    status: step.status === AGENT_STEP_STATUSES.DONE ? ("done" as const) : ("running" as const),
    details: step.asked.map(([ name, value ]) => ({ label: name, meta: value })),
  }))

  return <TaskRows rows={rows} className="w-full" />
}
