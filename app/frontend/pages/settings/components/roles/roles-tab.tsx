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
import { OptionDialog } from "@/pages/settings/components/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"

export function RolesTab({ roles }: { roles: IncidentRole[] }) {
  const [editing, setEditing] = useState<IncidentRole | null>(null)
  const [creating, setCreating] = useState(false)
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
          <Button size="sm" onClick={() => setCreating(true)}>
            <IconPlus className="size-4" />
            Add Role
          </Button>
        </div>
      </CardHeader>

      <CardContent className="p-0">
        <OptionsTable
          options={roles}
          nameHeader="Name"
          headers={
            <>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-28 text-center">Incidents</TableHead>
            </>
          }
          cells={(role) => (
            <>
              <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                <span className="flex items-center gap-2">
                  {role.description}
                  {role.system && <Badge variant="secondary" className="text-[10px]">Built in</Badge>}
                </span>
              </TableCell>
              <TableCell className="text-center">
                <Badge variant="outline" className="font-mono tabular-nums">{role.incidentCount}</Badge>
              </TableCell>
            </>
          )}
          onReorder={(orderedIds) =>
            router.patch(reorderIncidentRolesPath(), { ordered_ids: orderedIds }, { preserveScroll: true })}
          onToggleEnabled={(role) =>
            router.patch(
              role.enabled ? disableIncidentRolePath(role.id) : enableIncidentRolePath(role.id),
              {},
              { preserveScroll: true },
            )}
          onEdit={setEditing}
          onDelete={setDeleting}
        />
      </CardContent>

      <OptionDialog
        open={creating}
        onOpenChange={setCreating}
        title="Add Role"
        description="Create a new incident role for your workspace."
        submitLabel="Create Role"
        namePlaceholder="e.g. Operations Lead"
        descriptionPlaceholder="What is this role responsible for?"
        initial={{ name: "", description: "" }}
        action={incidentRolesPath()}
        method="post"
      />

      {editing && (
        <OptionDialog
          open
          onOpenChange={(open) => { if (!open) setEditing(null) }}
          title="Edit Role"
          description="Update the name or description for this role."
          submitLabel="Save Changes"
          initial={{ id: editing.id, name: editing.name, description: editing.description ?? "" }}
          action={incidentRolePath(editing.id)}
          method="patch"
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this role"}?`}
        description="No incidents use this role, so nothing loses its history. It disappears from the role picker straight away."
        onConfirm={() => {
          if (!deleting) return
          router.delete(incidentRolePath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
