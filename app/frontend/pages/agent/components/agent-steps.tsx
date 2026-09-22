import TaskRows, { type TaskRowStatus } from "@/components/agent-ui/task-rows"
import ThinkingState from "@/components/agent-ui/thinking-state"
import { AGENT_STEP_KINDS, AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import type { AgentStep, StepKind, StepStatus } from "@/pages/agent/types"

const ROW_STATUS: Record<StepStatus, TaskRowStatus> = {
  [AGENT_STEP_STATUSES.DONE]: "done",
  [AGENT_STEP_STATUSES.RUNNING]: "running",
  [AGENT_STEP_STATUSES.WAITING]: "waiting",
  [AGENT_STEP_STATUSES.CANCELLED]: "cancelled",
  [AGENT_STEP_STATUSES.FAILED]: "failed",
}

interface StepGroup {
  key: string
  kind: StepKind
  steps: AgentStep[]
}

interface AgentStepsProps {
  steps: AgentStep[]
}

export function AgentSteps({ steps }: AgentStepsProps) {
  return (
    <div className="flex flex-col gap-3">
      {groupedSteps(steps).map((group) =>
        group.kind === AGENT_STEP_KINDS.READ ? (
          <LookingUp key={group.key} steps={group.steps} />
        ) : (
          <TaskRows key={group.key} rows={group.steps.map(toRow)} className="w-full" />
        ),
      )}
    </div>
  )
}

// Looking something up is the agent thinking, so consecutive reads collapse into one trace rather than a card each.
function LookingUp({ steps }: { steps: AgentStep[] }) {
  const working = steps.some(isRunning)
  const seconds = steps.reduce((total, step) => total + step.seconds, 0)

  return (
    <ThinkingState
      rows={steps.map((step) => ({ id: step.key, primary: step.title, secondary: step.headline || undefined }))}
      active="Thinking"
      done={timeSpent(seconds)}
      working={working}
    />
  )
}

function groupedSteps(steps: AgentStep[]): StepGroup[] {
  return steps.reduce<StepGroup[]>((groups, step) => {
    const kind = isStepKind(step.kind) ? step.kind : AGENT_STEP_KINDS.ACT
    const open = groups[groups.length - 1]
    if (open && open.kind === kind) {
      open.steps.push(step)
      return groups
    }

    return [ ...groups, { key: step.key, kind, steps: [ step ] } ]
  }, [])
}

function toRow(step: AgentStep) {
  return {
    key: step.key,
    label: step.title,
    amount: step.headline,
    status: isStepStatus(step.status) ? ROW_STATUS[step.status] : ("running" as const),
    details: step.asked.map(([ name, value ]) => ({ label: name, meta: value })),
  }
}

function timeSpent(seconds: number) {
  if (seconds < 1) {
    return "Thought for a moment"
  }
  if (seconds === 1) {
    return "Thought for 1 second"
  }

  return `Thought for ${seconds} seconds`
}

function isRunning(step: AgentStep) {
  return step.status === AGENT_STEP_STATUSES.RUNNING
}

function isStepStatus(value: string): value is StepStatus {
  return Object.values<string>(AGENT_STEP_STATUSES).includes(value)
}

function isStepKind(value: string): value is StepKind {
  return Object.values<string>(AGENT_STEP_KINDS).includes(value)
}
