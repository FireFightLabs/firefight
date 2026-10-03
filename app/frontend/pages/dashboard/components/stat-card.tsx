import { IconTrendingDown, IconTrendingUp } from "@tabler/icons-react"

import type { DashboardStat } from "@/pages/dashboard/types"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardAction,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"

export function StatCard({ stat }: { stat: DashboardStat }) {
  const TrendIcon = stat.changeType === "up" ? IconTrendingUp : IconTrendingDown

  return (
    <Card className="@container/card border border-border">
      <CardHeader>
        <CardDescription className="text-fg-secondary">{stat.label}</CardDescription>
        <CardTitle className="text-2xl font-semibold tabular-nums text-fg-headline @[250px]/card:text-3xl">
          {stat.value}
        </CardTitle>
        {stat.change && (
          <CardAction>
            <Badge variant="outline" className="border-border-strong text-fg-body">
              <TrendIcon />
              {stat.change}
            </Badge>
          </CardAction>
        )}
      </CardHeader>
      <CardFooter className="flex-col items-start gap-2 pt-2 text-sm">
        <div className="line-clamp-1 flex items-center gap-2 font-medium text-fg-body">
          {stat.trendDescription}
        </div>
        <div className="text-fg-muted text-xs">{stat.detail}</div>
      </CardFooter>
    </Card>
  )
}
