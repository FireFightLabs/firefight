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
        <CardDescription>{stat.label}</CardDescription>
        <CardTitle className="text-2xl font-semibold tabular-nums @[250px]/card:text-3xl">
          {stat.value}
        </CardTitle>
        {stat.change && (
          <CardAction>
            <Badge variant="outline">
              <TrendIcon />
              {stat.change}
            </Badge>
          </CardAction>
        )}
      </CardHeader>
      <CardFooter className="flex-col items-start gap-2 pt-2 text-sm">
        <div className="line-clamp-1 flex items-center gap-2 font-medium text-foreground/80">
          {stat.trendDescription}
        </div>
        <div className="text-muted-foreground text-xs">{stat.detail}</div>
      </CardFooter>
    </Card>
  )
}
