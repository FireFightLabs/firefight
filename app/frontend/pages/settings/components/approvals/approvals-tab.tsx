import { router } from "@inertiajs/react"

import type { AbilityApproval } from "@/types/serializers"
import { approveApprovalPath, denyApprovalPath } from "@/lib/routes"
import { formatDateTime } from "@/lib/formatters"
import { useCan } from "@/lib/permissions"
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

const SOURCE_LABELS: Record<string, string> = {
  web: "Dashboard",
  slack: "Slack",
  api: "API",
  mcp: "Agent",
}

const STATUS_VARIANT: Record<string, "default" | "destructive" | "secondary" | "outline"> = {
  approved: "default",
  denied: "destructive",
  pending: "secondary",
  expired: "outline",
}

// A dashboard request is bound to its route, which reads better than the
// digest. Anything else shows as it was recorded.
function describeParams(params: Record<string, unknown>): string {
  if (typeof params.method === "string" && typeof params.path === "string") {
    return `${params.method} ${params.path}`
  }
  return JSON.stringify(params)
}

export function ApprovalsTab({
  pendingApprovals,
  resolvedApprovals,
}: {
  pendingApprovals: AbilityApproval[]
  resolvedApprovals: AbilityApproval[]
}) {
  const canDecide = useCan("approvals")
  function resolve(approval: AbilityApproval, decision: "approve" | "deny") {
    const path = decision === "approve" ? approveApprovalPath(approval.id) : denyApprovalPath(approval.id)
    router.post(path, {}, { preserveScroll: true })
  }

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Pending approvals</CardTitle>
          <CardDescription className="mt-1">
            Requests parked behind an approval policy. Approving admits exactly the parked request, once.
            A request from the dashboard or Slack then runs on its own, and an API or agent caller
            retries with the approval id.
          </CardDescription>
        </CardHeader>
        {pendingApprovals.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Requested</TableHead>
                  <TableHead>Requester</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead>Action</TableHead>
                  <TableHead>Details</TableHead>
                  <TableHead>Requires</TableHead>
                  {canDecide && <TableHead className="text-right">Decision</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingApprovals.map((approval) => (
                  <TableRow key={approval.id}>
                    <TableCell className="text-muted-foreground whitespace-nowrap">
                      {formatDateTime(approval.createdAt)}
                    </TableCell>
                    <TableCell>{approval.principalLabel}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {approval.source ? (SOURCE_LABELS[approval.source] ?? approval.source) : "-"}
                    </TableCell>
                    <TableCell>
                      <code className="text-xs">{approval.actionKey}</code>
                    </TableCell>
                    <TableCell className="text-muted-foreground max-w-64 truncate text-xs">
                      {describeParams(approval.params)}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{approval.requiredRole}</TableCell>
                    {canDecide && (
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-2">
                          <Button size="sm" onClick={() => resolve(approval, "approve")}>
                            Approve
                          </Button>
                          <Button size="sm" variant="destructive" onClick={() => resolve(approval, "deny")}>
                            Deny
                          </Button>
                        </div>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <p className="text-muted-foreground py-8 text-center text-sm">Nothing waiting for approval.</p>
          </CardContent>
        )}
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recently resolved</CardTitle>
        </CardHeader>
        {resolvedApprovals.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Requested</TableHead>
                  <TableHead>Requester</TableHead>
                  <TableHead>Action</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Resolved by</TableHead>
                  <TableHead>Resolved</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {resolvedApprovals.map((approval) => (
                  <TableRow key={approval.id}>
                    <TableCell className="text-muted-foreground whitespace-nowrap">
                      {formatDateTime(approval.createdAt)}
                    </TableCell>
                    <TableCell>{approval.principalLabel}</TableCell>
                    <TableCell>
                      <code className="text-xs">{approval.actionKey}</code>
                    </TableCell>
                    <TableCell>
                      <Badge variant={STATUS_VARIANT[approval.status] ?? "secondary"}>{approval.status}</Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{approval.approverName ?? "-"}</TableCell>
                    <TableCell className="text-muted-foreground whitespace-nowrap">
                      {approval.resolvedAt ? formatDateTime(approval.resolvedAt) : "-"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <p className="text-muted-foreground py-8 text-center text-sm">No resolved approvals yet.</p>
          </CardContent>
        )}
      </Card>
    </>
  )
}
