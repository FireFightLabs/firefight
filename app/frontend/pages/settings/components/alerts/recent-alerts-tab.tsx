import { IconBellRinging, IconRoute } from "@tabler/icons-react"
import { Link, router } from "@inertiajs/react"

import type { AlertSettings } from "@/types/serializers"
import { incidentPath, settingsAlertsPath, settingsAlertSourcesPath } from "@/lib/routes"
import { formatDateTime } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

const ALL_SOURCES = "all"

function StatusBadge({ status }: { status: string }) {
  if (status === "firing") return <Badge variant="destructive">Firing</Badge>
  return <Badge variant="secondary">Resolved</Badge>
}

function RoutingCell({ alert }: { alert: AlertSettings }) {
  if (alert.routingState === "routed") {
    if (alert.incidentId && alert.incidentIdentifier) {
      return (
        <Link href={incidentPath(alert.incidentId)} className="text-sm font-medium hover:underline">
          {alert.incidentIdentifier}
        </Link>
      )
    }
    return <Badge variant="outline">Routed</Badge>
  }
  if (alert.routingState === "unmatched") {
    return <span className="text-xs text-amber-500/90">Unmatched</span>
  }
  return <span className="text-xs text-muted-foreground/60">Pending</span>
}

export function RecentAlertsTab({
  alerts,
  alertSources,
  sourceId,
}: {
  alerts: AlertSettings[]
  alertSources: { id: string; name: string }[]
  sourceId: string | null
}) {
  function filterBySource(value: string) {
    router.get(settingsAlertsPath(), value === ALL_SOURCES ? {} : { source_id: value })
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Recent alerts</CardTitle>
            <CardDescription className="mt-1">
              The latest alerts received across your sources: how each was routed and which incident it created.
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Select value={sourceId ?? ALL_SOURCES} onValueChange={filterBySource}>
              <SelectTrigger className="w-44" size="sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_SOURCES}>All sources</SelectItem>
                {alertSources.map((source) => (
                  <SelectItem key={source.id} value={source.id}>{source.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button asChild variant="outline" size="sm">
              <Link href={settingsAlertSourcesPath()}>
                <IconRoute className="size-4" />
                Alert sources
              </Link>
            </Button>
          </div>
        </div>
      </CardHeader>
      {alerts.length > 0 ? (
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Alert</TableHead>
                <TableHead className="hidden md:table-cell">Source</TableHead>
                <TableHead className="w-24 text-center">Status</TableHead>
                <TableHead className="w-32">Routing</TableHead>
                <TableHead className="hidden w-20 text-center md:table-cell">Fired</TableHead>
                <TableHead className="w-36 text-right">Last seen</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {alerts.map((alert) => (
                <TableRow key={alert.id}>
                  <TableCell className="max-w-md">
                    <span className="block truncate text-sm font-medium">{alert.title}</span>
                  </TableCell>
                  <TableCell className="hidden text-sm text-muted-foreground md:table-cell">
                    {alert.sourceName}
                  </TableCell>
                  <TableCell className="text-center">
                    <StatusBadge status={alert.status} />
                  </TableCell>
                  <TableCell>
                    <RoutingCell alert={alert} />
                  </TableCell>
                  <TableCell className="hidden text-center font-mono text-xs text-muted-foreground md:table-cell">
                    {alert.eventCount}x
                  </TableCell>
                  <TableCell className="text-right text-xs text-muted-foreground">
                    {formatDateTime(alert.lastSeenAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      ) : (
        <CardContent>
          <div className="flex items-center gap-3 text-sm text-muted-foreground">
            <IconBellRinging className="size-4" />
            No alerts received yet. Point a monitoring tool at one of your alert source URLs and its alerts will show up here.
          </div>
        </CardContent>
      )}
    </Card>
  )
}
