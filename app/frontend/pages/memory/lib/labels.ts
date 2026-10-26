import { CHAT_MEMORY_STATE, type ChatMemoryState, LESSON_STATUS, type LessonStatus } from "@/lib/generated/constants"
import type { ChatLesson, ChatMemory } from "@/types/serializers"
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

export const LESSON_STATUS_LABELS: Record<LessonStatus, string> = {
  waiting: "Waiting for approval",
  approved: "Approved",
  turned_down: "Turned down",
}

export const LESSON_STATUS_TONES: Record<LessonStatus, string> = {
  waiting: "border-warning/35 bg-warning-tint text-warning",
  approved: "border-stage-closed-border bg-success-tint text-success",
  turned_down: "border-border-strong bg-stage-canceled-tint text-fg-muted",
}

// What pull request reviews do with it, in words, such as "Approved by Ada. Reviews comment on a pull request that goes
// against it."
export function lessonStanding(lesson: ChatLesson): string {
  if (lesson.status === LESSON_STATUS.TURNED_DOWN) {
    return lesson.turnedDownBy ? `Turned down by ${lesson.turnedDownBy}. Reviews never check it.` : "Turned down. Reviews never check it."
  }
  if (lesson.status === LESSON_STATUS.WAITING) {
    return "Reviews check it once the incident lead or an admin approves it."
  }
  const checks = lesson.strict ? "Reviews fail a check on a pull request that goes against it." : "Reviews comment on a pull request that goes against it."
  return lesson.approvedBy ? `Approved by ${lesson.approvedBy}. ${checks}` : checks
}
