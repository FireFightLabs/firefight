import { IconTrendingDown, IconTrendingUp } from "@tabler/icons-react"

import type { DashboardStat } from "@/modules/dashboard/types"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardAction,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"

function StatCard({ stat }: { stat: DashboardStat }) {
  const TrendIcon = stat.changeType === "up" ? IconTrendingUp : IconTrendingDown

  const borderClass =
    stat.highlight === "success"
      ? "border border-border border-l-2 border-l-[#5BD3A1]"
      : stat.highlight === "danger"
        ? "border border-border border-l-2 border-l-red-500"
        : "border border-border"

  const dotClass =
    stat.highlight === "success"
      ? "size-2 rounded-full bg-[#5BD3A1] shrink-0"
      : stat.highlight === "danger"
        ? "size-2 rounded-full bg-red-500 shrink-0"
        : null

  return (
    <Card className={`@container/card ${borderClass}`}>
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
      <CardFooter className="flex-col items-start gap-1.5 text-sm">
        <div className="line-clamp-1 flex items-center gap-2">
          {dotClass && <span className={dotClass} />}
          {stat.trendDescription}
        </div>
        <div className="text-muted-foreground text-xs">{stat.detail}</div>
      </CardFooter>
    </Card>
  )
}

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

export function StatCardsSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-4 px-4 lg:px-6 @xl/main:grid-cols-2 @5xl/main:grid-cols-4">
      {Array.from({ length: 4 }).map((_, i) => (
        <Card key={i} className="@container/card">
          <CardHeader>
            <Skeleton className="h-4 w-28" />
            <Skeleton className="h-8 w-16 mt-1" />
          </CardHeader>
          <CardFooter className="flex-col items-start gap-1.5">
            <Skeleton className="h-4 w-36" />
            <Skeleton className="h-3 w-44" />
          </CardFooter>
        </Card>
      ))}
    </div>
  )
}
