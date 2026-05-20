import type { DashboardStat } from "@/pages/dashboard/types"
import { StatCard } from "@/pages/dashboard/components/stat-card"

interface StatCardsProps {
  stats: DashboardStat[]
}

export function StatCards({ stats }: StatCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 px-4 lg:px-6 @xl/main:grid-cols-2 @5xl/main:grid-cols-4">
      {stats.map((stat) => (
        <StatCard key={stat.label} stat={stat} />
      ))}
    </div>
  )
}
