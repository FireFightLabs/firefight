import {
  CHAT_MEMORY_CHECK_OUTCOME, CHAT_MEMORY_EVENT_KIND, CHAT_MEMORY_STANDING, CHAT_MEMORY_STATE, type ChatMemoryEventKind, type ChatMemoryState,
} from "@/lib/generated/constants"
import { formatDate } from "@/lib/formatters"
import type { ChatMemory, ChatMemoryEvent } from "@/types/serializers"
import { MEMORY_FILTERS, type MemoryFilter } from "@/pages/memory/types"

export const FILTER_LABELS: Record<MemoryFilter, string> = {
  in_use: "In use",
  unconfirmed: "Unchecked",
  outdated: "Possibly outdated",
  disputed: "Disputed",
  expired: "Expired",
  rejected: "Rejected",
  merged: "Merged",
}

// Each filter past In use is one state. In use is whatever the server says Halon reads.
const FILTER_STATES: Record<Exclude<MemoryFilter, typeof MEMORY_FILTERS.IN_USE>, ChatMemoryState> = {
  [MEMORY_FILTERS.UNCONFIRMED]: CHAT_MEMORY_STATE.UNCONFIRMED,
  [MEMORY_FILTERS.OUTDATED]: CHAT_MEMORY_STATE.OUTDATED,
  [MEMORY_FILTERS.DISPUTED]: CHAT_MEMORY_STATE.DISPUTED,
  [MEMORY_FILTERS.EXPIRED]: CHAT_MEMORY_STATE.EXPIRED,
  [MEMORY_FILTERS.REJECTED]: CHAT_MEMORY_STATE.REJECTED,
  [MEMORY_FILTERS.MERGED]: CHAT_MEMORY_STATE.MERGED,
}

export function inFilter(memory: ChatMemory, filter: MemoryFilter): boolean {
  if (filter === MEMORY_FILTERS.IN_USE) {
    return memory.inUse
  }
  return FILTER_STATES[filter] === memory.state
}

// Who stands behind it, in words, such as "Confirmed by Ada, Oct 3" or "Checked by Halon, Oct 26". A postmortem nobody
// signed off is never read as a person, and neither is Halon.
export function vouch(memory: ChatMemory): string {
  return `${vouchedBy(memory)}, ${formatDate(vouchedAt(memory))}`
}

function vouchedBy(memory: ChatMemory): string {
  if (memory.rejectedBy) {
    return `Rejected by ${memory.rejectedBy}`
  }
  if (memory.state === CHAT_MEMORY_STATE.REJECTED) {
    return `Rejected${decidedBy(memory)}`
  }
  if (memory.state === CHAT_MEMORY_STATE.MERGED) {
    return "Merged by Halon"
  }
  if (memory.confirmedBy) {
    return `Confirmed by ${memory.confirmedBy}`
  }
  if (memory.state === CHAT_MEMORY_STATE.CONFIRMED) {
    return memory.decidedByHalon && !memory.decidedByPostmortem ? "Checked by Halon" : `Confirmed${decidedBy(memory)}`
  }
  return memory.addedBy ? `From a chat with ${memory.addedBy}` : "Learned by Halon"
}

// Who made a decision no person signed, as " by a postmortem" or " by Halon", or nothing.
function decidedBy(memory: ChatMemory): string {
  if (memory.decidedByPostmortem) {
    return " by a postmortem"
  }
  return memory.decidedByHalon ? " by Halon" : ""
}

// The events that set a memory aside, by the state they leave it in, so a rejected or merged memory is dated by that
// decision rather than an earlier confirmation.
const SET_ASIDE_BY: Partial<Record<ChatMemoryState, ChatMemoryEventKind[]>> = {
  [CHAT_MEMORY_STATE.REJECTED]: [ CHAT_MEMORY_EVENT_KIND.REJECTED, CHAT_MEMORY_EVENT_KIND.CORRECTED ],
  [CHAT_MEMORY_STATE.MERGED]: [ CHAT_MEMORY_EVENT_KIND.MERGED ],
}

function vouchedAt(memory: ChatMemory): string {
  if (memory.standing === CHAT_MEMORY_STANDING.HALON && memory.verifiedAt) {
    return memory.verifiedAt
  }
  const setAsideBy = SET_ASIDE_BY[memory.state]
  const setAside = setAsideBy && [ ...memory.events ].reverse().find((event) => setAsideBy.includes(event.kind))
  return setAside ? setAside.at : (memory.confirmedAt ?? memory.createdAt)
}

// What Halon's nightly check last found, said beside the memory, or null when there is nothing to say.
export function checkLine(memory: ChatMemory): string | null {
  if (memory.verifiedEvidence && memory.verifiedAt) {
    return `Halon checked it against production on ${formatDate(memory.verifiedAt)}. ${memory.verifiedEvidence}`
  }
  if (memory.standing !== CHAT_MEMORY_STANDING.UNCHECKED) {
    return null
  }
  if (memory.checkOutcome === CHAT_MEMORY_CHECK_OUTCOME.HELD && memory.checkedAt) {
    return `Halon found evidence against it on ${formatDate(memory.checkedAt)}, but left it as it was for now. The history says what it found.`
  }
  return memory.checkedAt ? `Halon could not check it yet. Last tried ${formatDate(memory.checkedAt)}.` : "Halon has not checked it yet."
}

export const EVENT_LABELS: Record<ChatMemoryEventKind, string> = {
  learned: "Learned",
  written: "Written on the Memory page",
  confirmed: "Confirmed",
  verified: "Checked against production and it held",
  unsettled: "Checked, but nothing showed it either way",
  held: "Checked and found otherwise, but left as it was",
  disputed: "Disputed",
  corrected: "Corrected",
  rejected: "Rejected",
  merged: "Merged into a memory that says the same",
  absorbed: "Took in a memory that said the same",
  outdated: "Flagged as possibly outdated",
  current_again: "No longer flagged as outdated",
  expired: "Expired",
  revived: "Learned again after it expired",
  restored: "Checked again, and it holds after all",
  still_wrong: "Checked again, and it is still wrong",
}

// The same, said after who did it, such as "Ada confirmed it".
const EVENT_ACTS: Record<ChatMemoryEventKind, string> = {
  learned: "added it",
  written: "wrote it on the Memory page",
  confirmed: "confirmed it",
  verified: "checked it against production and it held",
  unsettled: "checked it, but nothing showed it either way",
  held: "found otherwise, but left it as it was",
  disputed: "disputed it",
  corrected: "corrected it",
  rejected: "rejected it",
  merged: "merged it into a memory that says the same",
  absorbed: "merged a memory that said the same into it",
  outdated: "flagged it as possibly outdated",
  current_again: "cleared its outdated flag",
  expired: "set it aside as expired",
  revived: "learned it again after it expired",
  restored: "checked it again and it holds after all, so it is in use again",
  still_wrong: "checked it again and it is still wrong",
}

// One line of history, such as "Ada confirmed it", or "Expired" when nobody did it.
export function eventHeadline(event: ChatMemoryEvent): string {
  return event.by ? `${event.by} ${EVENT_ACTS[event.kind]}` : EVENT_LABELS[event.kind]
}
