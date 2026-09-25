import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import type { OPERATOR_STEP_STATUSES } from "@/lib/generated/constants"
import type { OperatorProcessEntry, OperatorWorkflowRow } from "@/types/serializers"

type ProcessTone = OperatorProcessEntry["tone"]
type WorkflowState = OperatorWorkflowRow["state"]
type StepStatus = (typeof OPERATOR_STEP_STATUSES)[keyof typeof OPERATOR_STEP_STATUSES]

// Uses the same colours as the investigation panel, so a failure looks the same in both places.
const PROCESS_TONES: Record<ProcessTone, Tone> = {
  ok: "emerald",
  info: "primary",
  warn: "amber",
  bad: "rose",
  idle: "neutral",
}

export const WORKFLOW_STATE_TONES: Record<WorkflowState, Tone> = {
  pending: "neutral",
  running: "primary",
  paused: "amber",
  succeeded: "emerald",
  failed: "rose",
  cancelled: "neutral",
}

export const STEP_STATUS_TONES: Record<StepStatus, Tone> = {
  pending: "neutral",
  running: "primary",
  succeeded: "emerald",
  failed: "rose",
  skipped: "neutral",
  cancelled: "neutral",
}

export function processToneClasses(tone: ProcessTone): string {
  return TONE_CLASSES[PROCESS_TONES[tone]]
}

export { TONE_CLASSES }
export type { Tone }
