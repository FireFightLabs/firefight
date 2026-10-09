import type { MEMORY_PAGE_TABS } from "@/lib/generated/constants"
import type { SharedProps } from "@/types"
import type { ChatInstruction, ChatMemory, MemorySubjectOption } from "@/types/serializers"

export type SubjectOption = MemorySubjectOption

export interface MemoryPageProps extends SharedProps {
  [key: string]: unknown
  memories: ChatMemory[]
  instructions: ChatInstruction[]
  subjects: SubjectOption[]
}

export type MemoryTab = (typeof MEMORY_PAGE_TABS)[keyof typeof MEMORY_PAGE_TABS]

// In use is what Halon reads. The rest wait on a person or were set aside.
export const MEMORY_FILTERS = {
  IN_USE: "in_use",
  UNCONFIRMED: "unconfirmed",
  OUTDATED: "outdated",
  DISPUTED: "disputed",
  EXPIRED: "expired",
  REJECTED: "rejected",
} as const
export type MemoryFilter = (typeof MEMORY_FILTERS)[keyof typeof MEMORY_FILTERS]

// Stands for no subject at all in a subject picker, which the server reads as the whole workspace.
export const WHOLE_WORKSPACE = "workspace"

export function subjectParam(value: string): string {
  return value === WHOLE_WORKSPACE ? "" : value
}
