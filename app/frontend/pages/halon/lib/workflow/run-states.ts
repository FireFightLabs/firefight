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

// How long something took, as 0.4s, 12s or 3m 4s, or nothing when it has not started.
export function durationLabel(startedAt: string | null | undefined, finishedAt: string | null | undefined): string {
  if (!startedAt) {
    return ""
  }
  const milliseconds = (finishedAt ? new Date(finishedAt) : new Date()).getTime() - new Date(startedAt).getTime()
  if (milliseconds < 10000) {
    return `${(milliseconds / 1000).toFixed(1)}s`
  }
  const seconds = Math.round(milliseconds / 1000)
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`
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
