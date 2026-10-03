import type { ChatMemoryState } from "@/lib/generated/constants"
import type { ChatMemory } from "@/types/serializers"
import { MEMORY_FILTERS, type MemoryFilter } from "@/pages/memory/types"

export const STATE_LABELS: Record<ChatMemoryState, string> = {
  unconfirmed: "Unconfirmed",
  confirmed: "Confirmed",
  disputed: "Disputed",
  outdated: "Possibly outdated",
  rejected: "Rejected",
}

export const STATE_TONES: Record<ChatMemoryState, string> = {
  unconfirmed: "border-stage-active-border bg-info-tint text-info",
  confirmed: "border-stage-closed-border bg-success-tint text-success",
  disputed: "border-error/35 bg-error-tint text-error",
  outdated: "border-warning/35 bg-warning-tint text-warning",
  rejected: "border-border-strong bg-stage-canceled-tint text-fg-muted",
}

export const FILTER_LABELS: Record<MemoryFilter, string> = {
  in_use: "In use",
  unconfirmed: "Unconfirmed",
  outdated: "Possibly outdated",
  disputed: "Disputed",
  rejected: "Rejected",
}

// Each filter past In use is one state. In use is whatever the server says Halon reads.
const FILTER_STATES: Record<Exclude<MemoryFilter, typeof MEMORY_FILTERS.IN_USE>, ChatMemoryState> = {
  [MEMORY_FILTERS.UNCONFIRMED]: "unconfirmed",
  [MEMORY_FILTERS.OUTDATED]: "outdated",
  [MEMORY_FILTERS.DISPUTED]: "disputed",
  [MEMORY_FILTERS.REJECTED]: "rejected",
}

export function inFilter(memory: ChatMemory, filter: MemoryFilter): boolean {
  if (filter === MEMORY_FILTERS.IN_USE) {
    return memory.inUse
  }
  return FILTER_STATES[filter] === memory.state
}

// Who stands behind it, in words, such as "Confirmed by Ada" or "From a chat with Ada".
export function vouch(memory: ChatMemory): string {
  if (memory.rejectedBy) {
    return `Rejected by ${memory.rejectedBy}`
  }
  if (memory.confirmedBy) {
    return `Confirmed by ${memory.confirmedBy}`
  }
  if (memory.state === "confirmed") {
    return "Confirmed by a postmortem"
  }
  return memory.addedBy ? `From a chat with ${memory.addedBy}` : "Learned by Halon"
}
