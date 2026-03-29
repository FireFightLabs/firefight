export const STATUS_OPTIONS = ["active", "closed"] as const
export type StatusOption = (typeof STATUS_OPTIONS)[number]

export const STATUS_LABELS: Record<StatusOption, string> = {
  active: "Active",
  closed: "Closed",
}
