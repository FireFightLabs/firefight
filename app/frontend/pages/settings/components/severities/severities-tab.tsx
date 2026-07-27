import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconGripVertical } from "@tabler/icons-react"

import type { IncidentSeveritySettings } from "@/types/serializers"
import {
  incidentSeverityPath,
  disableIncidentSeverityPath,
  enableIncidentSeverityPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AddSeverityDialog } from "@/pages/settings/components/severities/add-severity-dialog"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { EditSeverityDialog } from "@/pages/settings/components/severities/edit-severity-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"

interface SeveritiesTabProps {
  severities: IncidentSeveritySettings[]
}

function incidentsInUse(count: number) {
  return `${count} ${count === 1 ? "incident" : "incidents"}`
}

export function SeveritiesTab({ severities }: SeveritiesTabProps) {
  const [editingSeverity, setEditingSeverity] = useState<IncidentSeveritySettings | null>(null)
  const [deletingSeverity, setDeletingSeverity] = useState<IncidentSeveritySettings | null>(null)

  function handleToggleEnabled(severity: IncidentSeveritySettings) {
    router.patch(
      severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id)
    )
  }

  function confirmDelete() {
    if (!deletingSeverity) return
    router.delete(incidentSeverityPath(deletingSeverity.id), {
      onFinish: () => setDeletingSeverity(null),
    })
  }

  function deleteDisabledReason(severity: IncidentSeveritySettings) {
    if (severity.isDefault) return "This is the default severity. Pick a new default before deleting it."
    if (!severity.deletable) {
      return `In use by ${incidentsInUse(severity.incidentCount)}. Disable it instead to keep it off new incidents.`
    }
    return undefined
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Severities</CardTitle>
            <CardDescription className="mt-1">
              Define severity levels for classifying incident impact. Higher rank means more severe.
            </CardDescription>
          </div>
          <AddSeverityDialog />
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-8" />
              <TableHead>Severity</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-20 text-center">Rank</TableHead>
              <TableHead className="w-24 text-center">Default</TableHead>
              <TableHead className="w-24 text-center">Enabled</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {severities.map((severity) => (
              <TableRow key={severity.id} className={!severity.enabled ? "opacity-50" : undefined}>
                <TableCell>
                  {severity.enabled && (
                    <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2.5">
                    <ColorDot color={severity.color} />
                    <span className="font-medium">{severity.name}</span>
                  </div>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {severity.description}
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">
                    {severity.rank}
                  </Badge>
                </TableCell>
                <TableCell className="text-center">
                  {severity.isDefault && (
                    <Badge variant="secondary" className="text-xs">
                      Default
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-center">
                  <Switch
                    checked={severity.enabled}
                    disabled={severity.isDefault}
                    onCheckedChange={() => handleToggleEnabled(severity)}
                  />
                </TableCell>
                <TableCell>
                  <RowActions
                    onEdit={() => setEditingSeverity(severity)}
                    onDelete={() => setDeletingSeverity(severity)}
                    deleteDisabledReason={deleteDisabledReason(severity)}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>

      {editingSeverity && (
        <EditSeverityDialog
          severity={editingSeverity}
          open={!!editingSeverity}
          onOpenChange={(open) => { if (!open) setEditingSeverity(null) }}
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deletingSeverity)}
        title={`Delete ${deletingSeverity?.name ?? "this severity"}?`}
        description="No incidents use this severity, so nothing loses its history. It disappears from the declare form and from alert routing straight away."
        onConfirm={confirmDelete}
        onCancel={() => setDeletingSeverity(null)}
      />
    </Card>
  )
}
