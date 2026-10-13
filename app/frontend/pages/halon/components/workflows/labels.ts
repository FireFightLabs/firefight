import type {
  WorkflowFreezeBehaviour,
  WorkflowRunStatus,
  WorkflowScheduleRepeat,
  WorkflowState,
  WorkflowStepStatus,
} from "@/lib/generated/constants"
import { isKeyOf, labelFor } from "@/components/investigations/labels"
import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"

export const STATE_LABELS: Record<WorkflowState, string> = {
  draft: "Draft",
  live: "Live",
  changed: "Live, with changes in a draft",
  off: "Off",
  done: "Done",
}

export const RUN_STATUS_LABELS: Record<WorkflowRunStatus, string> = {
  queued: "Queued",
  running: "Running",
  waiting: "Waiting",
  paused: "Paused",
  succeeded: "Succeeded",
  failed: "Failed",
  cancelled: "Stopped",
}

export const STEP_STATUS_LABELS: Record<WorkflowStepStatus, string> = {
  pending: "Not started",
  running: "Running",
  waiting: "Waiting",
  succeeded: "Done",
  failed: "Failed",
  skipped: "Skipped",
  bypassed: "Not on the route taken",
  cancelled: "Stopped",
}

export const FREEZE_LABELS: Record<WorkflowFreezeBehaviour, string> = {
  wait: "Wait for the freeze to end",
  stop: "Stop the run",
}

export const REPEAT_LABELS: Record<WorkflowScheduleRepeat, string> = {
  minutes: "Every few minutes",
  hours: "Every few hours",
  days: "On days of the week",
  monthly: "Once a month",
}

// Tones a status is drawn in, the same across the list, a workflow's page and a run's page.
const STATE_TONES: Record<WorkflowState, Tone> = { draft: "neutral", live: "success", changed: "open", off: "neutral", done: "neutral" }
const RUN_TONES: Record<WorkflowRunStatus, Tone> = {
  queued: "neutral", running: "active", waiting: "active", paused: "warning", succeeded: "success", failed: "error", cancelled: "neutral",
}
const STEP_TONES: Record<WorkflowStepStatus, Tone> = {
  pending: "neutral", running: "active", waiting: "active", succeeded: "success", failed: "error", skipped: "neutral", bypassed: "neutral", cancelled: "neutral",
}

export function stateTone(state: string): string {
  return TONE_CLASSES[isKeyOf(STATE_TONES, state) ? STATE_TONES[state] : "neutral"]
}

export function runTone(status: string): string {
  return TONE_CLASSES[isKeyOf(RUN_TONES, status) ? RUN_TONES[status] : "neutral"]
}

export function stepTone(status: string): string {
  return TONE_CLASSES[isKeyOf(STEP_TONES, status) ? STEP_TONES[status] : "neutral"]
}

export function stateLabel(state: string): string {
  return labelFor(STATE_LABELS, state) ?? state
}

export function runStatusLabel(status: string): string {
  return labelFor(RUN_STATUS_LABELS, status) ?? status
}

export function stepStatusLabel(status: string): string {
  return labelFor(STEP_STATUS_LABELS, status) ?? status
}

// "Tue 13 Oct, 14:30", in the viewer's own time zone.
export function formatWhen(iso: string): string {
  return new Date(iso).toLocaleString(undefined, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })
}

export function dollars(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}
