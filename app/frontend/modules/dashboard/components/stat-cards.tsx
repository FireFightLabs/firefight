import { IconTrendingDown, IconTrendingUp } from "@tabler/icons-react"

import type { DashboardStat } from "@/modules/dashboard/types"
import { mockStats } from "@/modules/dashboard/lib/mock-data"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardAction,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"

function StatCard({ stat }: { stat: DashboardStat }) {
  const TrendIcon = stat.changeType === "up" ? IconTrendingUp : IconTrendingDown

  return (
    <Card className="@container/card">
      <CardHeader>
        <CardDescription>{stat.label}</CardDescription>
        <CardTitle className="text-2xl font-semibold tabular-nums @[250px]/card:text-3xl">
          {stat.value}
        </CardTitle>
        <CardAction>
          <Badge variant="outline">
            <TrendIcon />
            {stat.change}
          </Badge>
        </CardAction>
      </CardHeader>
      <CardFooter className="flex-col items-start gap-1.5 text-sm">
        <div className="line-clamp-1 flex gap-2 font-medium">
          {stat.trendDescription} <TrendIcon className="size-4" />
        </div>
        <div className="text-muted-foreground">{stat.detail}</div>
      </CardFooter>
    </Card>
  )
}

interface StatCardsProps {
  stats?: DashboardStat[]
}

export function StatCards({ stats = mockStats }: StatCardsProps) {
  return (
    <div className="grid grid-cols-1 gap-4 px-4 *:data-[slot=card]:bg-gradient-to-t *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card *:data-[slot=card]:shadow-xs lg:px-6 @xl/main:grid-cols-2 @5xl/main:grid-cols-4 dark:*:data-[slot=card]:bg-card">
      {stats.map((stat) => (
        <StatCard key={stat.label} stat={stat} />
      ))}
    </div>
  )
}
