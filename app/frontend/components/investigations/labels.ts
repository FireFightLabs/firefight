import type {
  FindingOutcome,
  RemediationPlanStatus,
  RemediationStepKind,
  RemediationStepStatus,
  HypothesisStatus,
  InvestigationStatus,
  InvestigationTrigger,
  LedgerDecision,
} from "@/lib/generated/constants"
import { formatTime } from "@/lib/formatters"

// How each kind of fix step gets done, as a person reads it.
export const REMEDIATION_STEP_LABELS: Record<RemediationStepKind, string> = {
  pull_request: "Code change",
  action: "Change through a tool",
  manual: "For a person",
}

// Where applying a fix has got to. A fix nobody applied yet shows no status.
export const FIX_STATUS_LABELS: Record<RemediationPlanStatus, string | null> = {
  proposed: null,
  applying: "Applying",
  applied: "Applied",
  partly_applied: "Partly applied",
  cancelled: "Cancelled",
}

// The same, for an undo.
export const UNDO_STATUS_LABELS: Record<RemediationPlanStatus, string | null> = {
  proposed: null,
  applying: "Undoing",
  applied: "Undone",
  partly_applied: "Partly undone",
  cancelled: "Cancelled",
}

export const FIX_STEP_STATUS_LABELS: Record<RemediationStepStatus, string | null> = {
  proposed: null,
  running: "Running",
  waiting_approval: "Waiting for approval",
  approved: "Approved, waiting for someone to run it",
  done: "Done",
  failed: "Failed",
  declined: "Declined",
  skipped: "Skipped, since a step it waits on did not go through",
}

export const STATUS_LABELS: Record<InvestigationStatus, string> = {
  pending: "Queued",
  running: "Investigating",
  succeeded: "Answered",
  failed: "Stopped",
  canceled: "Stopped",
}

export const TRIGGER_LABELS: Record<InvestigationTrigger, string> = {
  command: "/ff investigate",
  button: "Investigate button",
  conversation: "Chat",
  mcp: "Outside agent",
  dashboard: "Incident page",
  rehearsal: "Rehearsal",
}

export const HYPOTHESIS_LABELS: Record<HypothesisStatus, string> = {
  open: "Open",
  supported: "Supported",
  refuted: "Ruled out",
}

// How the story tells a theory once it is settled.
export const SETTLED_LABELS: Record<HypothesisStatus, string> = {
  open: "Still open",
  supported: "Confirmed",
  refuted: "Ruled out",
}

export const OUTCOME_LABELS: Record<FindingOutcome, string> = {
  confirmed: "Confirmed right",
  partial: "Partly right",
  wrong: "Wrong",
}

// What the rating buttons say, as Slack's do.
export const RATING_LABELS: Record<FindingOutcome, string> = {
  confirmed: "Right",
  partial: "Partly right",
  wrong: "Wrong",
}

export const DECISION_LABELS: Record<LedgerDecision, string> = {
  allow: "Allowed",
  deny: "Denied",
  pending: "Waiting for approval",
}

// The generated unions are narrower than the serialized strings, so a value is checked before it picks a label.
export function labelFor<Key extends string>(labels: Record<Key, string>, value: string | null | undefined): string | null {
  if (value == null) {
    return null
  }
  return isKeyOf(labels, value) ? labels[value] : value
}

export function isKeyOf<Key extends string>(record: Record<Key, unknown>, value: string): value is Key {
  return value in record
}

// The ledger's receipt for a step, such as "Allowed at 10:02".
export function receiptLine(receipt: { decision: string; at: string }): string {
  return `${labelFor(DECISION_LABELS, receipt.decision)} at ${formatTime(receipt.at)}`
}
