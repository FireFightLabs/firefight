import { WORKFLOW_STEP_STATUS } from "@/lib/generated/constants"
import type { StepRunState } from "@/pages/halon/lib/workflow/types"
import type { WorkflowRunRow, WorkflowRunStates } from "@/types/serializers"

type StepStatus = WorkflowRunStates["steps"][number]["status"]
type RunStatus = WorkflowRunRow["status"]
// A step's row in a run, as both the run shown and the newest run give it.
interface StepRow {
  stepKey: string
  iteration: string
  status: StepStatus
  startedAt?: string | null
  finishedAt?: string | null
  waitingApproval: boolean
}

export const STEP_STATUS_LABELS: Record<StepStatus, string> = {
  pending: "Not reached",
  running: "Running",
  waiting: "Waiting",
  succeeded: "Done",
  failed: "Failed",
  skipped: "Skipped",
  bypassed: "Not taken",
  cancelled: "Cancelled",
}

export const RUN_STATUS_LABELS: Record<RunStatus, string> = {
  queued: "Queued",
  running: "Running",
  waiting: "Waiting",
  paused: "Paused",
  succeeded: "Succeeded",
  failed: "Failed",
  cancelled: "Cancelled",
}

// A step still at work, whose log is still being written.
export const STEP_GOING: readonly StepStatus[] = [ WORKFLOW_STEP_STATUS.RUNNING, WORKFLOW_STEP_STATUS.WAITING ]

// The colour a state is told in, beside its words, never instead of them.
export const STEP_STATUS_TONES: Record<StepStatus, string> = {
  pending: "text-fg-muted",
  running: "text-warning",
  waiting: "text-warning",
  succeeded: "text-success",
  failed: "text-error",
  skipped: "text-fg-muted",
  bypassed: "text-fg-disabled",
  cancelled: "text-fg-muted",
}

export const RUN_STATUS_TONES: Record<RunStatus, string> = {
  queued: "border-border-strong text-fg-secondary",
  running: "border-warning-border bg-warning-tint text-warning",
  waiting: "border-warning-border bg-warning-tint text-warning",
  paused: "border-border-strong text-fg-secondary",
  succeeded: "border-success-border bg-success-tint text-success",
  failed: "border-error-border bg-error-tint text-error",
  cancelled: "border-border-strong text-fg-muted",
}

// How long something took, as 0.4s, 12s or 3m 4s, or nothing when it has not started. now is the moment a step still
// going counts to, which a ticking panel passes so the time moves between reloads.
export function durationLabel(startedAt: string | null | undefined, finishedAt: string | null | undefined, now: number = Date.now()): string {
  if (!startedAt) {
    return ""
  }
  const milliseconds = (finishedAt ? new Date(finishedAt).getTime() : now) - new Date(startedAt).getTime()
  if (milliseconds < 10000) {
    return `${(Math.max(milliseconds, 0) / 1000).toFixed(1)}s`
  }
  return secondsLabel(Math.round(milliseconds / 1000))
}

function secondsLabel(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}s`
  }
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`
}

// How long until a moment, as "in 35s" or "in 2m 10s", or "any moment now" once it is due.
export function untilLabel(at: string, now: number): string {
  const seconds = Math.round((new Date(at).getTime() - now) / 1000)
  return seconds <= 0 ? "any moment now" : `in ${secondsLabel(seconds)}`
}

// A moment to the second, in the viewer's own time, for a log where several lines land in one minute.
export function clockLabel(at: string): string {
  return new Date(at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" })
}

// One state for a step that ran once for each item of a for each: a failure or a wait shows first, then how many were done.
function combined(rows: StepRow[]): StepRunState {
  const waitingApproval = rows.some((row) => row.waitingApproval)
  const worst = [ WORKFLOW_STEP_STATUS.FAILED, WORKFLOW_STEP_STATUS.WAITING, WORKFLOW_STEP_STATUS.RUNNING ].find((status) => rows.some((row) => row.status === status))
  const done = rows.filter((row) => row.status === WORKFLOW_STEP_STATUS.SUCCEEDED).length
  return { status: worst ?? rows[0].status, label: `${done} of ${rows.length}`, waitingApproval }
}

// Each step's state in a run, by its id, for the canvas to draw on its node.
export function stepStates(rows: StepRow[]): Map<string, StepRunState> {
  const byKey = new Map<string, StepRow[]>()
  rows.forEach((row) => byKey.set(row.stepKey, [ ...(byKey.get(row.stepKey) ?? []), row ]))
  const states = new Map<string, StepRunState>()
  byKey.forEach((stepRows, key) => {
    if (stepRows.length > 1 || stepRows[0].iteration) {
      states.set(key, combined(stepRows))
      return
    }
    const row = stepRows[0]
    const timed = row.status === WORKFLOW_STEP_STATUS.SUCCEEDED || row.status === WORKFLOW_STEP_STATUS.FAILED
    states.set(key, { status: row.status, label: timed ? durationLabel(row.startedAt, row.finishedAt) : STEP_STATUS_LABELS[row.status], waitingApproval: row.waitingApproval })
  })
  return states
}
