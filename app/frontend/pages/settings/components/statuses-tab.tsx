import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconGripVertical } from "@tabler/icons-react"

import { toast } from "sonner"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import {
  incidentStatusPath,
  disableIncidentStatusPath,
  enableIncidentStatusPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
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
import { AddStatusDialog } from "@/pages/settings/components/add-status-dialog"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { EditStatusDialog } from "@/pages/settings/components/edit-status-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

interface StatusesTabProps {
  lifecycleStages: LifecycleStageWithStatuses[]
}

export function StatusesTab({ lifecycleStages }: StatusesTabProps) {
  const [editingStatus, setEditingStatus] = useState<IncidentStatusSettings | null>(null)

  function handleToggleEnabled(status: IncidentStatusSettings) {
    router.patch(
      status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id)
    )
  }

  function handleDelete(status: IncidentStatusSettings) {
    if (!status.deletable) {
      toast.error("This status is used by incidents and cannot be deleted. You can disable it instead.")
      return
    }
    router.delete(incidentStatusPath(status.id))
  }

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
        <Card key={stage.key}>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Badge
                  variant="secondary"
                  className={stageColors[stage.key]}
                >
                  {stage.name}
                </Badge>
                <CardDescription>{stage.description}</CardDescription>
              </div>
              <AddStatusDialog stage={stage} />
            </div>
          </CardHeader>
          {stage.statuses.length > 0 && (
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="w-8" />
                    <TableHead>Status</TableHead>
                    <TableHead className="hidden md:table-cell">Description</TableHead>
                    <TableHead className="w-24 text-center">Default</TableHead>
                    <TableHead className="w-24 text-center">Enabled</TableHead>
                    <TableHead className="w-12" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {stage.statuses.map((status) => (
                    <TableRow key={status.id} className={!status.enabled ? "opacity-50" : undefined}>
                      <TableCell>
                        {status.enabled && (
                          <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                        )}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2.5">
                          <ColorDot color={status.color} />
                          <span className="font-medium">{status.name}</span>
                        </div>
                      </TableCell>
                      <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                        {status.description}
                      </TableCell>
                      <TableCell className="text-center">
                        {status.isDefault && (
                          <Badge variant="secondary" className="text-xs">
                            Default
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-center">
                        <Switch
                          checked={status.enabled}
                          disabled={status.isDefault}
                          onCheckedChange={() => handleToggleEnabled(status)}
                        />
                      </TableCell>
                      <TableCell>
                        <RowActions
                          onEdit={() => setEditingStatus(status)}
                          onDelete={() => handleDelete(status)}
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          )}
        </Card>
      ))}

      {editingStatus && (
        <EditStatusDialog
          status={editingStatus}
          open={!!editingStatus}
          onOpenChange={(open) => { if (!open) setEditingStatus(null) }}
        />
      )}
    </div>
  )
}
