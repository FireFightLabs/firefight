import type { IncidentListItem } from "@/modules/incidents/types"

export type { IncidentListItem }

export interface DashboardStat {
  label: string
  value: string
  change: string
  changeType: "up" | "down"
  trendDescription: string
  detail: string
}
