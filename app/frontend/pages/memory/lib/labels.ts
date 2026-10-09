import type { ChatMemoryState } from "@/lib/generated/constants"
import type { ChatMemory } from "@/types/serializers"
import { MEMORY_FILTERS, type MemoryFilter } from "@/pages/memory/types"

export const FILTER_LABELS: Record<MemoryFilter, string> = {
  in_use: "In use",
  unconfirmed: "Unconfirmed",
  outdated: "Possibly outdated",
  disputed: "Disputed",
  expired: "Expired",
  rejected: "Rejected",
}

// Each filter past In use is one state. In use is whatever the server says Halon reads.
const FILTER_STATES: Record<Exclude<MemoryFilter, typeof MEMORY_FILTERS.IN_USE>, ChatMemoryState> = {
  [MEMORY_FILTERS.UNCONFIRMED]: "unconfirmed",
  [MEMORY_FILTERS.OUTDATED]: "outdated",
  [MEMORY_FILTERS.DISPUTED]: "disputed",
  [MEMORY_FILTERS.EXPIRED]: "expired",
  [MEMORY_FILTERS.REJECTED]: "rejected",
}

export function inFilter(memory: ChatMemory, filter: MemoryFilter): boolean {
  if (filter === MEMORY_FILTERS.IN_USE) {
    return memory.inUse
  }
  return FILTER_STATES[filter] === memory.state
}

// Who stands behind it, in words, such as "Confirmed by Ada" or "From a chat with Ada". A postmortem nobody signed off is
// never read as a person.
export function vouch(memory: ChatMemory): string {
  if (memory.rejectedBy) {
    return `Rejected by ${memory.rejectedBy}`
  }
  if (memory.state === "rejected" && memory.decidedByPostmortem) {
    return "Rejected by a postmortem"
  }
  if (memory.confirmedBy) {
    return `Confirmed by ${memory.confirmedBy}`
  }
  if (memory.state === "confirmed") {
    return memory.decidedByPostmortem ? "Confirmed by a postmortem" : "Confirmed"
  }
  return memory.addedBy ? `From a chat with ${memory.addedBy}` : "Learned by Halon"
}
