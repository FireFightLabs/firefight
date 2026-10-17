import { router } from "@inertiajs/react"

import type { AbilityApproval } from "@/types/serializers"
import { approveApprovalPath, denyApprovalPath } from "@/lib/routes"
import { formatDateTime, minutesInWords } from "@/lib/formatters"
import { APPROVAL_RUN_WINDOW_MINUTES } from "@/lib/generated/constants"
import { Blocked } from "@/components/blocked-tooltip"
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
import { ActionLabel } from "@/pages/settings/components/permissions/action-label"

const RUN_WINDOW = minutesInWords(APPROVAL_RUN_WINDOW_MINUTES)

const STATUS_VARIANT: Record<string, "default" | "destructive" | "secondary" | "outline"> = {
  approved: "default",
  denied: "destructive",
  pending: "secondary",
  expired: "outline",
  dismissed: "outline",
}

// A dashboard request is bound to its route, which reads better than the digest. A workflow's approval says what it asks.
function describeParams(approval: AbilityApproval): string {
  if (approval.question) {
    return approval.questionDetails ?? "-"
  }
  const params = approval.params
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
  // Approvals access decides every request, and a person a workflow's Approval step names decides that one, so the
  // column shows once any request here is theirs to decide, and each row says why when it is not.
  const canDecide = pendingApprovals.some((approval) => approval.decideDeniedReason == null)
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
            retries with the approval id. A call Halon made in a chat, or a step of a fix, never runs on
            approval. The person who asked runs it, within {RUN_WINDOW}.
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
                      {approval.sourceLabel ?? "-"}
                    </TableCell>
                    <TableCell>
                      <ActionLabel actionKey={approval.actionKey} title={approval.question ?? approval.connection} />
                      {approval.caution && (
                        <span className="mt-0.5 block max-w-80 text-xs font-medium text-amber-600 dark:text-amber-400">{approval.caution}</span>
                      )}
                    </TableCell>
                    <TableCell className="text-muted-foreground max-w-64 text-xs">
                      <span className="block truncate">{describeParams(approval)}</span>
                      {approval.rows.map(([ label, value ]) => (
                        <span key={label} className="block">{label}: {value}</span>
                      ))}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{approval.requiredRole}</TableCell>
                    {canDecide && (
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-2">
                          <Blocked reason={approval.decideDeniedReason ?? undefined} side="top">
                            <Button size="sm" disabled={approval.decideDeniedReason != null} onClick={() => resolve(approval, "approve")}>
                              Approve
                            </Button>
                          </Blocked>
                          <Blocked reason={approval.decideDeniedReason ?? undefined} side="top">
                            <Button size="sm" variant="destructive" disabled={approval.decideDeniedReason != null} onClick={() => resolve(approval, "deny")}>
                              Deny
                            </Button>
                          </Blocked>
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
                      <ActionLabel actionKey={approval.actionKey} title={approval.question ?? approval.connection} />
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
