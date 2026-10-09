import type { ChatMemoryState } from "@/lib/generated/constants"

export const STATE_LABELS: Record<ChatMemoryState, string> = {
  unconfirmed: "Unconfirmed",
  confirmed: "Confirmed",
  disputed: "Disputed",
  outdated: "Possibly outdated",
  rejected: "Rejected",
  expired: "Expired",
}

export const STATE_TONES: Record<ChatMemoryState, string> = {
  unconfirmed: "border-stage-active-border bg-info-tint text-info",
  confirmed: "border-stage-closed-border bg-success-tint text-success",
  disputed: "border-error/35 bg-error-tint text-error",
  outdated: "border-warning/35 bg-warning-tint text-warning",
  rejected: "border-border-strong bg-stage-canceled-tint text-fg-muted",
  expired: "border-border-strong bg-stage-canceled-tint text-fg-muted",
}
