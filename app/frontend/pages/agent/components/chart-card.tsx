import { usePage } from "@inertiajs/react"

import { MetricChart } from "@/components/charts/metric-chart"
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

  return (
    <div className={`grid w-full gap-2 ${shown.length > 1 ? "max-w-160 sm:grid-cols-2" : "max-w-110"}`}>
      {shown.map((chart) => (
        <section key={chart.id} className="rounded-card bg-surface px-3.5 py-3 shadow-card">
          <MetricChart chart={chart} />
        </section>
      ))}
    </div>
  )
}
