import { MetricChart } from "@/components/charts/metric-chart"
import type { ChatChart } from "@/types/serializers"

// One card per metric, two across when there is more than one.
export function ChartGrid({ charts }: { charts: ChatChart[] }) {
  return (
    <div className={`grid w-full gap-2 ${charts.length > 1 ? "max-w-160 sm:grid-cols-2" : "max-w-110"}`}>
      {charts.map((chart) => (
        <section key={chart.id} className="rounded-card bg-surface px-3.5 py-3 shadow-card">
          <MetricChart chart={chart} />
        </section>
      ))}
    </div>
  )
}
