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

// Their task row wants a headline beside the name. Ours is what the agent searched for or named. A
// call with neither, only a limit say, shows no headline, and every argument is still in the details.
const HEADLINE_ARGUMENTS = [ "query", "name", "identifier", "title" ]

function headline(step: AgentStep): string {
  const named = HEADLINE_ARGUMENTS.map((wanted) => step.asked.find(([ name ]) => name === wanted)).find(Boolean)

  return named ? named[1] : ""
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
