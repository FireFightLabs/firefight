import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import type { IncidentSeveritySettings } from "@/types/serializers"
import {
  incidentSeveritiesPath,
  incidentSeverityPath,
  disableIncidentSeverityPath,
  enableIncidentSeverityPath,
  makeDefaultIncidentSeverityPath,
  reorderIncidentSeveritiesPath,
} from "@/lib/routes"
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
import { OptionDialog } from "@/pages/settings/components/options/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options/options-table"

export function SeveritiesTab({ severities }: { severities: IncidentSeveritySettings[] }) {
  const [editing, setEditing] = useState<IncidentSeveritySettings | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<IncidentSeveritySettings | null>(null)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Severities</CardTitle>
            <CardDescription className="mt-1">
              Define severity levels for classifying incident impact. Drag to reorder, most severe at the top.
            </CardDescription>
          </div>
          <Button size="sm" onClick={() => setCreating(true)}>
            <IconPlus className="size-4" />
            Add Severity
          </Button>
        </div>
      </CardHeader>

      <CardContent className="p-0">
        <OptionsTable
          options={severities}
          nameHeader="Severity"
          headers={<TableHead className="hidden md:table-cell">Description</TableHead>}
          cells={(severity) => (
            <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
              {severity.description}
            </TableCell>
          )}
          onReorder={(orderedIds) =>
            router.patch(reorderIncidentSeveritiesPath(), { ordered_ids: orderedIds }, { preserveScroll: true })}
          onMakeDefault={(id) =>
            router.patch(makeDefaultIncidentSeverityPath(id), {}, { preserveScroll: true })}
          onToggleEnabled={(severity) =>
            router.patch(
              severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id),
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
        title="Add Severity"
        description="Create a new severity level for your workspace."
        submitLabel="Create Severity"
        namePlaceholder="e.g. Moderate"
        descriptionPlaceholder="When should this severity be assigned?"
        initial={{ name: "", description: "", color: "#FF6B35" }}
        action={incidentSeveritiesPath()}
        method="post"
        footnote={
          <p className="text-xs text-muted-foreground">
            New severities are added at the bottom as the least severe. Drag to move it up the list.
          </p>
        }
      />

      {editing && (
        <OptionDialog
          open
          onOpenChange={(open) => { if (!open) setEditing(null) }}
          title="Edit Severity"
          description="Update the name, description, or color for this severity level."
          submitLabel="Save Changes"
          initial={{
            id: editing.id,
            name: editing.name,
            description: editing.description ?? "",
            color: editing.color,
          }}
          action={incidentSeverityPath(editing.id)}
          method="patch"
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this severity"}?`}
        description="No incidents use this severity, so nothing loses its history. It disappears from the declare form and from alert routing straight away."
        onConfirm={() => {
          if (!deleting) return
          router.delete(incidentSeverityPath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
