import { LIFECYCLE_STAGES } from "@/lib/constants"

export const DEFAULT_PER_PAGE = 20

export const SEARCH_DEBOUNCE_MS = 300

export const STATUS_OPTIONS = [LIFECYCLE_STAGES.ACTIVE, LIFECYCLE_STAGES.CLOSED] as const
export type StatusOption = (typeof STATUS_OPTIONS)[number]

export const STATUS_LABELS: Record<StatusOption, string> = {
  [LIFECYCLE_STAGES.ACTIVE]: "Active",
  [LIFECYCLE_STAGES.CLOSED]: "Closed",
}
