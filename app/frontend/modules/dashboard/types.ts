export interface DashboardStat {
  label: string
  value: string
  change?: string
  changeType?: "up" | "down"
  trendDescription: string
  detail: string
}

export interface Pagination {
  page: number
  perPage: number
  totalCount: number
  totalPages: number
}

export interface DashboardFilters {
  search: string
  severities: string[]
  statuses: string[]
}