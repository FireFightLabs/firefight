export interface DashboardStat {
  label: string
  value: string
  change: string
  changeType: "up" | "down"
  trendDescription: string
  detail: string
}
