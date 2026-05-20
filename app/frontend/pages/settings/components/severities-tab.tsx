import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconGripVertical } from "@tabler/icons-react"

import { toast } from "sonner"

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
import { AddSeverityDialog } from "@/pages/settings/components/add-severity-dialog"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { EditSeverityDialog } from "@/pages/settings/components/edit-severity-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"

interface SeveritiesTabProps {
  severities: IncidentSeveritySettings[]
}

export function SeveritiesTab({ severities }: SeveritiesTabProps) {
  const [editingSeverity, setEditingSeverity] = useState<IncidentSeveritySettings | null>(null)

  function handleToggleEnabled(severity: IncidentSeveritySettings) {
    router.patch(
      severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id)
    )
  }

  function handleDelete(severity: IncidentSeveritySettings) {
    if (!severity.deletable) {
      toast.error("This severity is used by incidents and cannot be deleted. You can disable it instead.")
      return
    }
    router.delete(incidentSeverityPath(severity.id))
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
                    onDelete={() => handleDelete(severity)}
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
    </Card>
  )
}
