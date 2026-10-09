import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import { OPERATOR_PROCESS_TONES, OPERATOR_STEP_STATUSES, OPERATOR_WORKFLOW_STATES } from "@/pages/operator/generated/constants"
import type { OperatorProcessEntry, OperatorWorkflowRow } from "@/types/serializers"

type ProcessTone = OperatorProcessEntry["tone"]
type WorkflowState = OperatorWorkflowRow["state"]
type StepStatus = (typeof OPERATOR_STEP_STATUSES)[keyof typeof OPERATOR_STEP_STATUSES]

// Uses the same colours as the investigation panel, so a failure looks the same in both places.
const PROCESS_TONES: Record<ProcessTone, Tone> = {
  [OPERATOR_PROCESS_TONES.OK]: "success",
  [OPERATOR_PROCESS_TONES.INFO]: "active",
  [OPERATOR_PROCESS_TONES.WARN]: "warning",
  [OPERATOR_PROCESS_TONES.BAD]: "error",
  [OPERATOR_PROCESS_TONES.IDLE]: "neutral",
}

export const WORKFLOW_STATE_TONES: Record<WorkflowState, Tone> = {
  [OPERATOR_WORKFLOW_STATES.PENDING]: "neutral",
  [OPERATOR_WORKFLOW_STATES.RUNNING]: "active",
  [OPERATOR_WORKFLOW_STATES.PAUSED]: "warning",
  [OPERATOR_WORKFLOW_STATES.SUCCEEDED]: "success",
  [OPERATOR_WORKFLOW_STATES.FAILED]: "error",
  [OPERATOR_WORKFLOW_STATES.CANCELLED]: "neutral",
}

export const STEP_STATUS_TONES: Record<StepStatus, Tone> = {
  [OPERATOR_STEP_STATUSES.PENDING]: "neutral",
  [OPERATOR_STEP_STATUSES.RUNNING]: "active",
  [OPERATOR_STEP_STATUSES.SUCCEEDED]: "success",
  [OPERATOR_STEP_STATUSES.FAILED]: "error",
  [OPERATOR_STEP_STATUSES.SKIPPED]: "neutral",
  [OPERATOR_STEP_STATUSES.CANCELLED]: "neutral",
}

export function processToneClasses(tone: ProcessTone): string {
  return TONE_CLASSES[PROCESS_TONES[tone]]
}

export { TONE_CLASSES }
export type { Tone }
