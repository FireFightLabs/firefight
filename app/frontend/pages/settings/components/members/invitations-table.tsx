import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconDotsVertical } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { resendWorkspaceInvitationPath, workspaceInvitationPath } from "@/lib/routes"
import type { WorkspaceInvitation } from "@/types/serializers"

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })
}

function InvitationActions({
  invitation,
  canManage,
  onRevoke,
}: {
  invitation: WorkspaceInvitation
  canManage: boolean
  onRevoke: (invitation: WorkspaceInvitation) => void
}) {
  function resend() {
    router.post(resendWorkspaceInvitationPath(invitation.id), {}, { preserveScroll: true })
  }

  function revoke() {
    onRevoke(invitation)
  }

  if (!canManage) {
    return null
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
          <IconDotsVertical className="size-4" />
          <span className="sr-only">Invitation actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-40">
        <DropdownMenuItem onSelect={resend}>Resend</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem variant="destructive" onSelect={revoke}>Revoke</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export function InvitationsTable({ invitations, canManage }: { invitations: WorkspaceInvitation[]; canManage: boolean }) {
  const [revoking, setRevoking] = useState<WorkspaceInvitation | null>(null)

  function cancelRevoke() {
    setRevoking(null)
  }

  function confirmRevoke() {
    if (!revoking) {
      return
    }
    router.delete(workspaceInvitationPath(revoking.id), { preserveScroll: true, onFinish: cancelRevoke })
  }

  return (
    <>
      <Card className="overflow-hidden py-0">
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Email</TableHead>
                <TableHead>Invited by</TableHead>
                <TableHead>Sent</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {invitations.map((invitation) => (
                <TableRow key={invitation.id}>
                  <TableCell className="font-medium text-foreground">{invitation.email}</TableCell>
                  <TableCell className="text-sm text-muted-foreground">{invitation.invitedByName ?? "-"}</TableCell>
                  <TableCell className="text-sm text-muted-foreground tabular-nums">
                    <span className="flex items-center gap-2">
                      {formatDate(invitation.sentAt)}
                      {invitation.expired ? (
                        <Badge variant="secondary" className="font-normal">Expired</Badge>
                      ) : null}
                    </span>
                  </TableCell>
                  <TableCell className="text-right">
                    <InvitationActions invitation={invitation} canManage={canManage} onRevoke={setRevoking} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <ConfirmDeleteDialog
        open={revoking !== null}
        title="Revoke invitation?"
        description={
          revoking
            ? `The link sent to ${revoking.email} stops working. You can invite them again later.`
            : ""
        }
        confirmLabel="Revoke"
        onConfirm={confirmRevoke}
        onCancel={cancelRevoke}
      />
    </>
  )
}
