import type { IncidentListItem } from "@/types/serializers"
import type { DashboardStat } from "@/modules/dashboard/types"

export const mockIncidents: IncidentListItem[] = [
  { id: "1", identifier: "INC-042", name: "Payment processing failures in EU region", severity: { name: "Critical", rank: 4 }, status: { name: "Investigating", lifecycleStage: "active" }, lead: "Sarah Chen", declaredAt: "2026-03-25T08:15:00Z", resolvedAt: null },
  { id: "2", identifier: "INC-041", name: "Elevated API latency on /v2/orders endpoint", severity: { name: "High", rank: 3 }, status: { name: "Monitoring", lifecycleStage: "active" }, lead: "James Wilson", declaredAt: "2026-03-25T06:30:00Z", resolvedAt: null },
  { id: "3", identifier: "INC-040", name: "CDN cache invalidation delays", severity: { name: "Medium", rank: 2 }, status: { name: "Investigating", lifecycleStage: "active" }, lead: null, declaredAt: "2026-03-24T22:00:00Z", resolvedAt: null },
  { id: "4", identifier: "INC-039", name: "Database connection pool exhaustion", severity: { name: "Critical", rank: 4 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "Maria Garcia", declaredAt: "2026-03-24T14:20:00Z", resolvedAt: "2026-03-24T15:45:00Z" },
  { id: "5", identifier: "INC-038", name: "SSO login failures for SAML customers", severity: { name: "High", rank: 3 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "Alex Kim", declaredAt: "2026-03-24T09:10:00Z", resolvedAt: "2026-03-24T10:30:00Z" },
  { id: "6", identifier: "INC-037", name: "Email notification delivery delays", severity: { name: "Low", rank: 1 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "Jordan Park", declaredAt: "2026-03-23T16:45:00Z", resolvedAt: "2026-03-23T17:20:00Z" },
  { id: "7", identifier: "INC-036", name: "Mobile app crash on iOS 19.2", severity: { name: "High", rank: 3 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "Sarah Chen", declaredAt: "2026-03-23T11:00:00Z", resolvedAt: "2026-03-23T13:15:00Z" },
  { id: "8", identifier: "INC-035", name: "Webhook delivery failures to partner endpoints", severity: { name: "Medium", rank: 2 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "James Wilson", declaredAt: "2026-03-22T19:30:00Z", resolvedAt: "2026-03-22T20:45:00Z" },
  { id: "9", identifier: "INC-034", name: "Search index replication lag across clusters", severity: { name: "Medium", rank: 2 }, status: { name: "Triage", lifecycleStage: "active" }, lead: null, declaredAt: "2026-03-25T09:45:00Z", resolvedAt: null },
  { id: "10", identifier: "INC-033", name: "Scheduled reports generating with stale data", severity: { name: "Low", rank: 1 }, status: { name: "Resolved", lifecycleStage: "closed" }, lead: "Maria Garcia", declaredAt: "2026-03-21T14:00:00Z", resolvedAt: "2026-03-21T15:30:00Z" },
]

export const mockStats: DashboardStat[] = [
  { label: "Active Incidents", value: "7", change: "+2", changeType: "up", trendDescription: "2 more than last week", detail: "Currently open and being worked on" },
  { label: "MTTR", value: "45 min", change: "-12%", changeType: "down", trendDescription: "Down 12% from last month", detail: "Mean time to resolve incidents" },
  { label: "Total Incidents", value: "23", change: "+8%", changeType: "up", trendDescription: "Up from 21 last month", detail: "Incidents declared this month" },
  { label: "Critical Incidents", value: "3", change: "-1", changeType: "down", trendDescription: "1 fewer than last month", detail: "P1 severity incidents this month" },
]
