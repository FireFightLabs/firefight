import type { OPERATOR_WINDOWS } from "@/lib/generated/constants"
import type { OperatorHalonRun } from "@/types/serializers"

export interface OperatorPageProps extends Record<string, unknown> {
  operator: { name: string; email: string } | null
  // What needs a person in the last day, counted for the nav.
  attention?: number
}

export type OperatorWindow = (typeof OPERATOR_WINDOWS)[keyof typeof OPERATOR_WINDOWS]

// The window and workspace a page reads, echoed back with what the pickers offer.
export interface FilterProps {
  filter: { window: OperatorWindow; workspace: string | null }
  windows: OperatorWindow[]
  workspaces: { id: string; name: string }[]
}

export interface IncidentsSummary {
  declared: number
  fromAlerts: number
  platformFailures: number
  webhooksFailed: number
  webhooksSent: number
  alertsWaiting: number
  oldestAlertAt: string | null
}

export interface WorkflowsSummary {
  ran: number
  failed: number
  retrying: number
  paused: number
  kinds: number
}

export interface JobsSummary {
  finished: number
  failed: number
  waiting: number
  oldestWaitingAt: string | null
  workers: number
  workersAlive: number
}

export interface HalonSummary {
  runs: number
  chatTurns: number
  answered: number
  finished: number
  stopped: number
  failed: number
  spentMicros: number
}

export interface HalonTotals {
  runs: number
  live: number
  chatTurns: number
  answered: number
  finished: number
  medianSeconds: number | null
  p90Seconds: number | null
  spentMicros: number
  medianRunMicros: number | null
}

export interface HalonBucket {
  at: string
  answered: number
  stopped: number
  failed: number
  live: number
}

export interface HalonReason {
  reason: string
  ending: OperatorHalonRun["ending"]
  count: number
}

export interface HalonTool {
  actionKey: string
  calls: number
  errors: number
  denied: number
  medianMs: number | null
}

export interface HalonModel {
  calls: number
  errors: number
  medianMs: number | null
  p90Ms: number | null
  errorClasses: Record<string, number>
}

export interface HalonPrompt {
  version: string
  firstSeenAt: string
  text: string
  runs: number
  answered: number
  finished: number
  medianTurns: number | null
  medianMicros: number | null
  confirmed: number
  wrong: number
}
