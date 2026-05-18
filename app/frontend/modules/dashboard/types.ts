export interface DashboardStat {
  label: string
  value: string
  change?: string
  changeType?: "up" | "down"
  trendDescription: string
  detail: string
  highlight?: "success" | "danger"
}

export interface DashboardFilters {
  search: string
  severities: string[]
  statuses: string[]
}