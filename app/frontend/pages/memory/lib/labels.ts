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
  unconfirmed: "border-amber-400/30 bg-amber-400/10 text-amber-300",
  confirmed: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300",
  disputed: "border-red-400/30 bg-red-400/10 text-red-300",
  outdated: "border-orange-400/30 bg-orange-400/10 text-orange-300",
  rejected: "border-border bg-muted/40 text-muted-foreground",
}

export const FILTER_LABELS: Record<MemoryFilter, string> = {
  in_use: "In use",
  unconfirmed: "Unconfirmed",
  outdated: "Possibly outdated",
  disputed: "Disputed",
  rejected: "Rejected",
}

const FILTER_STATES: Record<MemoryFilter, ChatMemoryState[]> = {
  [MEMORY_FILTERS.IN_USE]: [ "confirmed", "unconfirmed", "outdated" ],
  [MEMORY_FILTERS.UNCONFIRMED]: [ "unconfirmed" ],
  [MEMORY_FILTERS.OUTDATED]: [ "outdated" ],
  [MEMORY_FILTERS.DISPUTED]: [ "disputed" ],
  [MEMORY_FILTERS.REJECTED]: [ "rejected" ],
}

export function inFilter(memory: ChatMemory, filter: MemoryFilter): boolean {
  return FILTER_STATES[filter].includes(memory.state)
}

// Who stands behind it, in words, such as "Confirmed by Ada" or "Taught by Ada".
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
  return memory.addedBy ? `Taught by ${memory.addedBy}` : "Learned by Halon"
}
