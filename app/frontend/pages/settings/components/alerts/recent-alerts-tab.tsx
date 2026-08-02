import { IconBellRinging, IconRoute } from "@tabler/icons-react"
import { Link, router } from "@inertiajs/react"

import type { AlertSettings } from "@/types/serializers"
import { settingsAlertsPath, settingsAlertSourcesPath } from "@/lib/routes"
import { formatDateTime } from "@/lib/formatters"
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
import { StatusBadge } from "@/pages/settings/components/alerts/status-badge"
import { RoutingCell } from "@/pages/settings/components/alerts/routing-cell"
import { MatchedRuleCell } from "@/pages/settings/components/alerts/matched-rule-cell"

const ALL = "all"

export function RecentAlertsTab({
  alerts,
  alertSources,
  sourceId,
  ruleId,
  ruleOptions,
}: {
  alerts: AlertSettings[]
  alertSources: { id: string; name: string }[]
  sourceId: string | null
  ruleId: string | null
  ruleOptions: { id: string; label: string }[]
}) {
  function applyFilters(nextSourceId: string | null, nextRuleId: string | null) {
    const params: Record<string, string> = {}
    if (nextSourceId) {
      params.source_id = nextSourceId
    }
    if (nextRuleId) {
      params.rule_id = nextRuleId
    }
    router.get(settingsAlertsPath(), params)
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Recent alerts</CardTitle>
            <CardDescription className="mt-1">
              The latest alerts received across your sources: how each was routed, which rule matched, and
              which incident it created.
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Select
              value={sourceId ?? ALL}
              onValueChange={(value) => applyFilters(value === ALL ? null : value, null)}
            >
              <SelectTrigger className="w-44" size="sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All sources</SelectItem>
                {alertSources.map((source) => (
                  <SelectItem key={source.id} value={source.id}>{source.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {ruleOptions.length > 0 && (
              <Select
                value={ruleId ?? ALL}
                onValueChange={(value) => applyFilters(sourceId, value === ALL ? null : value)}
              >
                <SelectTrigger className="w-56" size="sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL}>All rules</SelectItem>
                  {ruleOptions.map((rule) => (
                    <SelectItem key={rule.id} value={rule.id}>{rule.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
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
                <TableHead className="hidden w-32 lg:table-cell">Matched rule</TableHead>
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
                  <TableCell className="hidden lg:table-cell">
                    <MatchedRuleCell alert={alert} />
                  </TableCell>
                  <TableCell className="hidden text-center font-mono text-xs text-muted-foreground md:table-cell">
                    {alert.eventCount}x
                  </TableCell>
                  <TableCell className="text-right text-xs text-muted-foreground" title={alert.lastSeenAt}>
                    {formatDateTime(alert.lastSeenAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      ) : (
        <CardContent>
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 text-sm text-muted-foreground">
              <IconBellRinging className="size-4" />
              No alerts received yet. Point a monitoring tool at one of your alert source URLs and its alerts will show up here.
            </div>
            <Button asChild size="sm" variant="outline">
              <Link href={settingsAlertSourcesPath()}>Set up a source</Link>
            </Button>
          </div>
        </CardContent>
      )}
    </Card>
  )
}
