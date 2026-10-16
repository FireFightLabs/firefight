import { useState } from "react"
import { router } from "@inertiajs/react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { RowActions } from "@/components/row-actions"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import type { WorkspaceMembership } from "@/types/serializers"
import { initialsOf } from "@/lib/initials"
import { restoreWorkspaceMembershipPath, workspaceMembershipPath } from "@/lib/routes"

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

function counted(count: number, one: string, many: string) {
  return `${count} ${count === 1 ? one : many}`
}

// What removing takes away, named so the admin knows before they confirm.
function removalWords(member: WorkspaceMembership, workspaceName: string) {
  const losses = [
    member.personalTokenCount > 0 ? counted(member.personalTokenCount, "personal token", "personal tokens") : null,
    member.connectedAgentCount > 0 ? counted(member.connectedAgentCount, "connected agent", "connected agents") : null,
  ].filter((loss): loss is string => loss !== null)
  const single = member.personalTokenCount + member.connectedAgentCount === 1
  const stopping = losses.length > 0 ? ` Their ${losses.join(" and ")} ${single ? "stops" : "stop"} working for good.` : ""
  return `${member.name} loses access to ${workspaceName} at once and is signed out of it.${stopping} ` +
    "Incidents and history that name them stay, and you can add them back later."
}

function PersonCell({ member }: { member: WorkspaceMembership }) {
  return (
    <div className="flex items-center gap-3">
      <Avatar className="size-8">
        {member.avatarUrl ? (
          <AvatarImage src={member.avatarUrl} alt={member.name} />
        ) : null}
        <AvatarFallback>{initialsOf(member.name)}</AvatarFallback>
      </Avatar>
      <div className="leading-tight">
        <div className="font-medium text-foreground">{member.name}</div>
        <div className="text-xs text-muted-foreground">
          {member.email}
        </div>
      </div>
    </div>
  )
}

export function MembersTable({
  members,
  canManage,
  workspaceName,
}: {
  members: WorkspaceMembership[]
  canManage: boolean
  workspaceName: string
}) {
  const [removing, setRemoving] = useState<WorkspaceMembership | null>(null)

  function confirmRemove() {
    if (!removing) {
      return
    }
    router.delete(workspaceMembershipPath(removing.id))
    setRemoving(null)
  }

  function keepMember() {
    setRemoving(null)
  }

  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Person</TableHead>
              <TableHead>Access</TableHead>
              <TableHead>Joined</TableHead>
              {canManage ? <TableHead className="w-12" /> : null}
            </TableRow>
          </TableHeader>
          <TableBody>
            {members.map((member) => (
              <TableRow key={member.id}>
                <TableCell>
                  <PersonCell member={member} />
                </TableCell>
                <TableCell>
                  <Badge variant="secondary" className="font-normal">
                    {member.role}
                  </Badge>
                </TableCell>
                <TableCell className="text-sm text-muted-foreground tabular-nums">
                  {formatDate(member.joinedAt)}
                </TableCell>
                {canManage ? (
                  <TableCell>
                    <RowActions
                      onDelete={() => setRemoving(member)}
                      deleteLabel="Remove"
                      deleteDisabledReason={member.removalBlockedReason ?? undefined}
                    />
                  </TableCell>
                ) : null}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
      {canManage ? (
        <ConfirmDeleteDialog
          open={removing !== null}
          title={`Remove ${removing?.name ?? "this member"}?`}
          description={removing ? removalWords(removing, workspaceName) : ""}
          confirmLabel="Remove"
          onConfirm={confirmRemove}
          onCancel={keepMember}
        />
      ) : null}
    </Card>
  )
}

// People an admin removed, kept so they can be added back, since their row still holds their history.
export function RemovedMembersTable({ members, canManage }: { members: WorkspaceMembership[]; canManage: boolean }) {
  function addBack(member: WorkspaceMembership) {
    router.post(restoreWorkspaceMembershipPath(member.id))
  }

  return (
    <Card className="overflow-hidden py-0">
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Person</TableHead>
              <TableHead>Removed</TableHead>
              {canManage ? <TableHead className="w-28" /> : null}
            </TableRow>
          </TableHeader>
          <TableBody>
            {members.map((member) => (
              <TableRow key={member.id}>
                <TableCell>
                  <PersonCell member={member} />
                </TableCell>
                <TableCell className="text-sm text-muted-foreground tabular-nums">
                  {member.removedAt ? formatDate(member.removedAt) : "-"}
                </TableCell>
                {canManage ? (
                  <TableCell className="text-right">
                    {member.removalBlockedReason ? (
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <span>
                            <Button variant="outline" size="sm" disabled>
                              Add back
                            </Button>
                          </span>
                        </TooltipTrigger>
                        <TooltipContent>{member.removalBlockedReason}</TooltipContent>
                      </Tooltip>
                    ) : (
                      <Button variant="outline" size="sm" onClick={() => addBack(member)}>
                        Add back
                      </Button>
                    )}
                  </TableCell>
                ) : null}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
