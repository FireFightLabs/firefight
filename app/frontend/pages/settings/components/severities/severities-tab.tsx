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
import { HeaderHint } from "@/pages/settings/components/header-hint"
import { OptionDialog, type OptionDialogState } from "@/pages/settings/components/option-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { slugColumnHint } from "@/pages/settings/lib/constants"

export function SeveritiesTab({ severities }: { severities: IncidentSeveritySettings[] }) {
  const [dialog, setDialog] = useState<OptionDialogState<IncidentSeveritySettings>>(null)
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
          <Button size="sm" onClick={() => setDialog({ mode: "create" })}>
            <IconPlus className="size-4" />
            Add Severity
          </Button>
        </div>
      </CardHeader>

      <CardContent className="p-0">
        <OptionsTable
          options={severities}
          nameHeader="Severity"
          headers={
            <>
              <TableHead className="hidden lg:table-cell">
                <HeaderHint
                  label="Slug"
                  hint={slugColumnHint("severity")}
                />
              </TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
            </>
          }
          cells={(severity) => (
            <>
              <TableCell className="hidden lg:table-cell">
                <span className="font-mono text-[12px] text-muted-foreground">{severity.slug}</span>
              </TableCell>
              <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                {severity.description}
              </TableCell>
            </>
          )}
          reorderPath={reorderIncidentSeveritiesPath()}
          onMakeDefault={(id) =>
            router.patch(makeDefaultIncidentSeverityPath(id), {}, { preserveScroll: true })}
          onToggleEnabled={(severity) =>
            router.patch(
              severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id),
              {},
              { preserveScroll: true },
            )}
          onEdit={(option) => setDialog({ mode: "edit", option })}
          onDelete={setDeleting}
        />
      </CardContent>

      <OptionDialog
        state={dialog}
        onClose={() => setDialog(null)}
        noun="Severity"
        createPath={incidentSeveritiesPath()}
        editPath={incidentSeverityPath}
        defaultColor="#FF6B35"
        namePlaceholder="e.g. Moderate"
        descriptionPlaceholder="When should this severity be assigned?"
        footnote={
          <p className="text-xs text-muted-foreground">
            New severities are added at the bottom as the least severe. Drag to move it up the list.
          </p>
        }
      />

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
