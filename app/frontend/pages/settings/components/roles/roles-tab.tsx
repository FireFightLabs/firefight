import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import type { IncidentRole } from "@/types/serializers"
import {
  incidentRolesPath,
  incidentRolePath,
  disableIncidentRolePath,
  enableIncidentRolePath,
  reorderIncidentRolesPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionDialog, type OptionDialogState } from "@/pages/settings/components/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"

export function RolesTab({ roles, canManage }: { roles: IncidentRole[]; canManage: boolean }) {
  const [dialog, setDialog] = useState<OptionDialogState<IncidentRole>>(null)
  const [deleting, setDeleting] = useState<IncidentRole | null>(null)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Incident Roles</CardTitle>
            <CardDescription className="mt-1">
              Define the roles that can be assigned to team members during an incident. Drag to reorder.
            </CardDescription>
          </div>
          {canManage && (
            <Button size="sm" onClick={() => setDialog({ mode: "create" })}>
              <IconPlus className="size-4" />
              Add Role
            </Button>
          )}
        </div>
      </CardHeader>

      <CardContent className="p-0">
        <OptionsTable
          options={roles}
          nameHeader="Name"
          headers={<TableHead className="hidden md:table-cell">Description</TableHead>}
          cells={(role) => (
            <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
              <span className="flex items-center gap-2">
                {role.description}
                {role.system && <Badge variant="secondary" className="text-[10px]">Built in</Badge>}
              </span>
            </TableCell>
          )}
          reorderPath={reorderIncidentRolesPath()}
          onToggleEnabled={(role) =>
            router.patch(
              role.enabled ? disableIncidentRolePath(role.id) : enableIncidentRolePath(role.id),
              {},
              { preserveScroll: true },
            )}
          onEdit={(option) => setDialog({ mode: "edit", option })}
          onDelete={setDeleting}
          readOnly={!canManage}
        />
      </CardContent>

      <OptionDialog
        state={dialog}
        onClose={() => setDialog(null)}
        noun="Role"
        createPath={incidentRolesPath()}
        editPath={incidentRolePath}
        namePlaceholder="e.g. Operations Lead"
        descriptionPlaceholder="What is this role responsible for?"
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this role"}?`}
        description="No incidents use this role, so nothing loses its history. It disappears from the role picker straight away."
        onConfirm={() => {
          if (!deleting) {
            return
          }
          router.delete(incidentRolePath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
