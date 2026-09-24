import type {
  FindingOutcome,
  HypothesisStatus,
  InvestigationStatus,
  InvestigationStepStatus,
  InvestigationTrigger,
  LedgerDecision,
} from "@/lib/generated/constants"

export const STATUS_LABELS: Record<InvestigationStatus, string> = {
  pending: "Queued",
  running: "Investigating",
  succeeded: "Answered",
  failed: "Stopped",
  canceled: "Stopped",
}

export const TRIGGER_LABELS: Record<InvestigationTrigger, string> = {
  command: "/ff investigate",
  button: "the Investigate button",
  conversation: "a chat",
  mcp: "an outside agent",
  rehearsal: "a rehearsal",
}

export const HYPOTHESIS_LABELS: Record<HypothesisStatus, string> = {
  open: "Open",
  supported: "Supported",
  refuted: "Ruled out",
}

export const STEP_LABELS: Record<InvestigationStepStatus, string> = {
  pending: "Waiting",
  running: "Running",
  succeeded: "Done",
  failed: "Failed",
}

export const OUTCOME_LABELS: Record<FindingOutcome, string> = {
  confirmed: "Confirmed right",
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
