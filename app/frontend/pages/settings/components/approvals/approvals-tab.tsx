import { router } from "@inertiajs/react"

import type { AbilityApproval } from "@/types/serializers"
import { approveApprovalPath, denyApprovalPath } from "@/lib/routes"
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

const STATUS_VARIANT: Record<string, "default" | "destructive" | "secondary" | "outline"> = {
  approved: "default",
  denied: "destructive",
  pending: "secondary",
  expired: "outline",
}

export function ApprovalsTab({
  pendingApprovals,
  resolvedApprovals,
}: {
  pendingApprovals: AbilityApproval[]
  resolvedApprovals: AbilityApproval[]
}) {
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
            Calls parked behind an approval policy. Approving admits exactly the parked call, once.
            The requester then retries with the approval id.
          </CardDescription>
        </CardHeader>
        {pendingApprovals.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Requested</TableHead>
                  <TableHead>Requester</TableHead>
                  <TableHead>Action</TableHead>
                  <TableHead>Details</TableHead>
                  <TableHead>Requires</TableHead>
                  <TableHead className="text-right">Decision</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingApprovals.map((approval) => (
                  <TableRow key={approval.id}>
                    <TableCell className="text-muted-foreground whitespace-nowrap">
                      {formatDateTime(approval.createdAt)}
                    </TableCell>
                    <TableCell>{approval.principalLabel}</TableCell>
                    <TableCell>
                      <code className="text-xs">{approval.actionKey}</code>
                    </TableCell>
                    <TableCell className="text-muted-foreground max-w-64 truncate text-xs">
                      {JSON.stringify(approval.params)}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{approval.requiredRole}</TableCell>
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
