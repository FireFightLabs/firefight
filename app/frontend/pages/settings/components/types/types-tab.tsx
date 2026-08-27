import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconCategory, IconPlus } from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import {
  incidentTypesPath,
  incidentTypePath,
  disableIncidentTypePath,
  enableIncidentTypePath,
  reorderIncidentTypesPath,
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
import { HeaderHint } from "@/pages/settings/components/header-hint"
import { OptionDialog, type OptionDialogState } from "@/pages/settings/components/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { slugColumnHint } from "@/pages/settings/lib/constants"

const DEFAULT_TYPE_COLOR = "#6366F1"

export function TypesTab({ types, canManage }: { types: IncidentTypeSettings[]; canManage: boolean }) {
  const [dialog, setDialog] = useState<OptionDialogState<IncidentTypeSettings>>(null)
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
          {canManage && (
            <Button size="sm" onClick={() => setDialog({ mode: "create" })}>
              <IconPlus className="size-4" />
              Add Type
            </Button>
          )}
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
            {canManage && (
              <Button size="sm" variant="outline" className="mt-4" onClick={() => setDialog({ mode: "create" })}>
                <IconPlus className="size-3.5" />
                Create your first type
              </Button>
            )}
          </div>
        ) : (
          <OptionsTable
            options={types}
            nameHeader="Type"
            fallbackColor={DEFAULT_TYPE_COLOR}
            headers={
              <>
                <TableHead className="hidden w-44 lg:table-cell">
                  <HeaderHint
                    label="Slug"
                    hint={slugColumnHint("type")}
                  />
                </TableHead>
                <TableHead className="hidden md:table-cell">Description</TableHead>
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
              </>
            )}
            reorderPath={reorderIncidentTypesPath()}
            onToggleEnabled={(type) =>
              router.patch(
                type.enabled ? disableIncidentTypePath(type.id) : enableIncidentTypePath(type.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={(option) => setDialog({ mode: "edit", option })}
            onDelete={setDeleting}
            readOnly={!canManage}
          />
        )}
      </CardContent>

      <OptionDialog
        state={dialog}
        onClose={() => setDialog(null)}
        noun="Type"
        createDescription="Create a new incident type for your workspace."
        createPath={incidentTypesPath()}
        editPath={incidentTypePath}
        defaultColor={DEFAULT_TYPE_COLOR}
        namePlaceholder="e.g. Outage, Degradation, Security"
        descriptionPlaceholder="When should this type be used?"
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this type"}?`}
        description="No incidents use this type, so nothing loses its history. It disappears from the declare form straight away."
        onConfirm={() => {
          if (!deleting) {
            return
          }
          router.delete(incidentTypePath(deleting.id), { preserveScroll: true, onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
