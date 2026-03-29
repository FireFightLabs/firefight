export const DEFAULT_PER_PAGE = 20

export const PAGE_SIZE_OPTIONS = [10, 20, 30, 40, 50] as const

export const STATUS_OPTIONS = ["active", "closed"] as const
export type StatusOption = (typeof STATUS_OPTIONS)[number]

export const STATUS_LABELS: Record<StatusOption, string> = {
  active: "Active",
  closed: "Closed",
}
