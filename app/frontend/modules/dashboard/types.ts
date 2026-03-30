export interface DashboardStat {
  label: string
  value: string
  change?: string
  changeType?: "up" | "down"
  trendDescription: string
  detail: string
}

export interface DashboardFilters {
  search: string
  severities: string[]
  statuses: string[]
}