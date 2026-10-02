import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import type { OPERATOR_STEP_STATUSES } from "@/lib/generated/constants"
import type { OperatorProcessEntry, OperatorWorkflowRow } from "@/types/serializers"

type ProcessTone = OperatorProcessEntry["tone"]
type WorkflowState = OperatorWorkflowRow["state"]
type StepStatus = (typeof OPERATOR_STEP_STATUSES)[keyof typeof OPERATOR_STEP_STATUSES]

// Uses the same colours as the investigation panel, so a failure looks the same in both places.
const PROCESS_TONES: Record<ProcessTone, Tone> = {
  ok: "success",
  info: "active",
  warn: "warning",
  bad: "error",
  idle: "neutral",
}

export const WORKFLOW_STATE_TONES: Record<WorkflowState, Tone> = {
  pending: "neutral",
  running: "active",
  paused: "warning",
  succeeded: "success",
  failed: "error",
  cancelled: "neutral",
}

export const STEP_STATUS_TONES: Record<StepStatus, Tone> = {
  pending: "neutral",
  running: "active",
  succeeded: "success",
  failed: "error",
  skipped: "neutral",
  cancelled: "neutral",
}

export function processToneClasses(tone: ProcessTone): string {
  return TONE_CLASSES[PROCESS_TONES[tone]]
}

export { TONE_CLASSES }
export type { Tone }
