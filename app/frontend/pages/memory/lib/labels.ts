import { CHAT_MEMORY_STATE, type ChatMemoryState } from "@/lib/generated/constants"
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
  [MEMORY_FILTERS.UNCONFIRMED]: CHAT_MEMORY_STATE.UNCONFIRMED,
  [MEMORY_FILTERS.OUTDATED]: CHAT_MEMORY_STATE.OUTDATED,
  [MEMORY_FILTERS.DISPUTED]: CHAT_MEMORY_STATE.DISPUTED,
  [MEMORY_FILTERS.EXPIRED]: CHAT_MEMORY_STATE.EXPIRED,
  [MEMORY_FILTERS.REJECTED]: CHAT_MEMORY_STATE.REJECTED,
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
  if (memory.state === CHAT_MEMORY_STATE.REJECTED && memory.decidedByPostmortem) {
    return "Rejected by a postmortem"
  }
  if (memory.confirmedBy) {
    return `Confirmed by ${memory.confirmedBy}`
  }
  if (memory.state === CHAT_MEMORY_STATE.CONFIRMED) {
    return memory.decidedByPostmortem ? "Confirmed by a postmortem" : "Confirmed"
  }
  return memory.addedBy ? `From a chat with ${memory.addedBy}` : "Learned by Halon"
}
