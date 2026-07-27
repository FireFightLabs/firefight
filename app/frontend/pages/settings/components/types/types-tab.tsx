import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconCategory, IconPlus } from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import {
  incidentTypesPath,
  incidentTypePath,
  disableIncidentTypePath,
  enableIncidentTypePath,
  makeDefaultIncidentTypePath,
  reorderIncidentTypesPath,
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
import { OptionDialog } from "@/pages/settings/components/options/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options/options-table"

const DEFAULT_TYPE_COLOR = "#6366F1"

export function TypesTab({ types }: { types: IncidentTypeSettings[] }) {
  const [editing, setEditing] = useState<IncidentTypeSettings | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<IncidentTypeSettings | null>(null)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Incident Types</CardTitle>
            <CardDescription className="mt-1">
              Classify incidents by type to organize your response process and reporting.
            </CardDescription>
          </div>
          <Button size="sm" onClick={() => setCreating(true)}>
            <IconPlus className="size-4" />
            Add type
          </Button>
        </div>
      </CardHeader>

      <CardContent className={types.length === 0 ? undefined : "p-0"}>
        {types.length === 0 ? (
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconCategory className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No incident types yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Create types like Outage, Degradation, or Security to classify incidents and drive type-specific workflows.
            </p>
            <Button size="sm" variant="outline" className="mt-4" onClick={() => setCreating(true)}>
              <IconPlus className="size-3.5" />
              Create your first type
            </Button>
          </div>
        ) : (
          <OptionsTable
            options={types}
            nameHeader="Type"
            fallbackColor={DEFAULT_TYPE_COLOR}
            headers={
              <>
                <TableHead className="hidden lg:table-cell">Slug</TableHead>
                <TableHead className="hidden md:table-cell">Description</TableHead>
                <TableHead className="w-28 text-center">Incidents</TableHead>
              </>
            }
            cells={(type) => (
              <>
                <TableCell className="hidden lg:table-cell">
                  <span className="font-mono text-[12px] text-muted-foreground">{type.slug}</span>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {type.description}
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">{type.incidentCount}</Badge>
                </TableCell>
              </>
            )}
            onReorder={(orderedIds) =>
              router.patch(reorderIncidentTypesPath(), { ordered_ids: orderedIds }, { preserveScroll: true })}
            onMakeDefault={(id) =>
              router.patch(makeDefaultIncidentTypePath(id), {}, { preserveScroll: true })}
            onToggleEnabled={(type) =>
              router.patch(
                type.enabled ? disableIncidentTypePath(type.id) : enableIncidentTypePath(type.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={setEditing}
            onDelete={setDeleting}
          />
        )}
      </CardContent>

      <OptionDialog
        open={creating}
        onOpenChange={setCreating}
        title="Add incident type"
        description="Create a new incident type for your workspace."
        submitLabel="Create type"
        namePlaceholder="e.g. Outage, Degradation, Security"
        descriptionPlaceholder="When should this type be used?"
        initial={{ name: "", description: "", color: DEFAULT_TYPE_COLOR }}
        action={incidentTypesPath()}
        method="post"
      />

      {editing && (
        <OptionDialog
          open
          onOpenChange={(open) => { if (!open) setEditing(null) }}
          title="Edit incident type"
          description="Update the name, description, or color. The default is set from the list."
          submitLabel="Save changes"
          initial={{
            id: editing.id,
            name: editing.name,
            description: editing.description ?? "",
            color: editing.color ?? DEFAULT_TYPE_COLOR,
          }}
          action={incidentTypePath(editing.id)}
          method="patch"
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this type"}?`}
        description="No incidents use this type, so nothing loses its history. It disappears from the declare form straight away."
        onConfirm={() => {
          if (!deleting) return
          router.delete(incidentTypePath(deleting.id), { preserveScroll: true, onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
