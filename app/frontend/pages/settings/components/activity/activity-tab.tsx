import { router } from "@inertiajs/react"

import type { AbilityInvocation } from "@/types/serializers"
import { settingsActivityPath } from "@/lib/routes"
import { formatDateTime } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
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

const ALL = "all"
const DECISIONS = ["allow", "deny", "pending"] as const

const DECISION_VARIANT: Record<string, "default" | "destructive" | "secondary"> = {
  allow: "default",
  deny: "destructive",
  pending: "secondary",
}

export function ActivityTab({
  invocations,
  decision,
}: {
  invocations: AbilityInvocation[]
  decision: string | null
}) {
  function applyFilter(nextDecision: string | null) {
    router.get(settingsActivityPath(), nextDecision ? { decision: nextDecision } : {})
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Activity</CardTitle>
            <CardDescription className="mt-1">
              The gateway ledger: every governed action agents and API keys performed, were denied, or
              have pending approval.
            </CardDescription>
          </div>
          <Select
            value={decision ?? ALL}
            onValueChange={(value) => applyFilter(value === ALL ? null : value)}
          >
            <SelectTrigger className="w-36">
              <SelectValue placeholder="All decisions" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All decisions</SelectItem>
              {DECISIONS.map((value) => (
                <SelectItem key={value} value={value}>
                  {value}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </CardHeader>
      <CardContent>
        {invocations.length === 0 ? (
          <p className="text-muted-foreground py-8 text-center text-sm">
            No governed activity yet. Actions taken by agents and API keys will appear here.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>When</TableHead>
                <TableHead>Principal</TableHead>
                <TableHead>Action</TableHead>
                <TableHead>Decision</TableHead>
                <TableHead>Outcome</TableHead>
                <TableHead className="text-right">Duration</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {invocations.map((invocation) => (
                <TableRow key={invocation.id}>
                  <TableCell className="text-muted-foreground whitespace-nowrap">
                    {formatDateTime(invocation.createdAt)}
                  </TableCell>
                  <TableCell>{invocation.principalLabel}</TableCell>
                  <TableCell>
                    <code className="text-xs">{invocation.actionKey}</code>
                  </TableCell>
                  <TableCell>
                    <Badge variant={DECISION_VARIANT[invocation.decision] ?? "secondary"}>
                      {invocation.decision}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {invocation.outcome ?? (invocation.decision === "allow" && !invocation.completedAt ? "unknown" : "-")}
                    {invocation.errorSummary ? ` (${invocation.errorSummary})` : ""}
                  </TableCell>
                  <TableCell className="text-muted-foreground text-right">
                    {invocation.durationMs != null ? `${invocation.durationMs} ms` : "-"}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
