import { usePage } from "@inertiajs/react"

import { ChartGrid } from "@/pages/agent/components/chart-grid"
import type { AgentPageProps } from "@/pages/agent/types"

interface ChartCardProps {
  toolCallKey: string
}

// The charts a tool returned, found by the tool call that made them, one card per metric.
export function ChartCard({ toolCallKey }: ChartCardProps) {
  const { charts } = usePage<AgentPageProps>().props
  const shown = (charts ?? []).filter((chart) => chart.toolCallId === toolCallKey)
  if (shown.length === 0) {
    return null
  }

  return <ChartGrid charts={shown} />
}
