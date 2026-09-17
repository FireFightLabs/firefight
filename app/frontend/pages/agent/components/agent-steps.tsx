import TaskRows from "@/components/agent-ui/task-rows"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"

// A step reads the same whether it is arriving over the socket or read back from the saved chat.
export interface AgentStep {
  key: string
  title: string
  asked: [ string, string ][]
  status: string
}

interface AgentStepsProps {
  steps: AgentStep[]
}

// Their task row wants a headline figure beside the name. Ours is what the agent asked the tool for.
function headline(step: AgentStep): string {
  const [ first ] = step.asked

  return first ? first[1] : ""
}

export function AgentSteps({ steps }: AgentStepsProps) {
  const rows = steps.map((step) => ({
    key: step.key,
    label: step.title,
    amount: headline(step),
    status: step.status === AGENT_STEP_STATUSES.DONE ? ("done" as const) : ("running" as const),
    details: step.asked.map(([ name, value ]) => ({ label: name, meta: value })),
  }))

  return <TaskRows rows={rows} className="w-full" />
}
