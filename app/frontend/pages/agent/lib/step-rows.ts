import type { ThinkingRowStatus } from "@/components/agent-ui/thinking-state"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import type { StepStatus } from "@/pages/agent/types"

// How a step's status is drawn as a row of the trace, the chat's own steps and a helper's alike.
export const ROW_STATUSES: Record<StepStatus, ThinkingRowStatus> = {
  [AGENT_STEP_STATUSES.RUNNING]: "running",
  [AGENT_STEP_STATUSES.DONE]: "done",
  [AGENT_STEP_STATUSES.FAILED]: "failed",
  [AGENT_STEP_STATUSES.NOT_FOUND]: "not_found",
  [AGENT_STEP_STATUSES.REFUSED]: "refused",
  [AGENT_STEP_STATUSES.WAITING]: "waiting",
  [AGENT_STEP_STATUSES.CANCELLED]: "cancelled",
}

export function rowStatus(status: string): ThinkingRowStatus {
  return isStepStatus(status) ? ROW_STATUSES[status] : "running"
}

function isStepStatus(value: string): value is StepStatus {
  return Object.values<string>(AGENT_STEP_STATUSES).includes(value)
}
