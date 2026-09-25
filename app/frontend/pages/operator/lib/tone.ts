import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import type { OperatorProcessEntry, OperatorWorkflowRow } from "@/types/serializers"

type ProcessTone = OperatorProcessEntry["tone"]
type WorkflowState = OperatorWorkflowRow["state"]
type StepStatus = { status: "pending" | "running" | "succeeded" | "failed" | "skipped" | "cancelled" }["status"]

// The console speaks in the same colours as the investigation panel, so a failure reads the same everywhere.
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
