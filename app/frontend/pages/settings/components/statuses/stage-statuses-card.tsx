import { router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import {
  disableIncidentStatusPath,
  enableIncidentStatusPath,
  makeDefaultIncidentStatusPath,
  reorderIncidentStatusesPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
} from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { OptionsTable } from "@/pages/settings/components/options-table"

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

export function StageStatusesCard({
  stage,
  onCreate,
  onEdit,
  onDelete,
}: {
  stage: LifecycleStageWithStatuses
  onCreate: (stage: LifecycleStageWithStatuses) => void
  onEdit: (status: IncidentStatusSettings) => void
  onDelete: (status: IncidentStatusSettings) => void
}) {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Badge variant="secondary" className={stageColors[stage.key]}>{stage.name}</Badge>
            <CardDescription>{stage.description}</CardDescription>
          </div>
          <Button size="sm" onClick={() => onCreate(stage)}>
            <IconPlus className="size-4" />
            Add Status
          </Button>
        </div>
      </CardHeader>
      {stage.statuses.length > 0 && (
        <CardContent className="p-0">
          <OptionsTable
            options={stage.statuses}
            nameHeader="Status"
            headers={<TableHead className="hidden md:table-cell">Description</TableHead>}
            cells={(status) => (
              <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                {status.description}
              </TableCell>
            )}
            reorderPath={reorderIncidentStatusesPath()}
            reorderParams={{ lifecycle_stage_key: stage.key }}
            fixedLayout
            onMakeDefault={(id) =>
              router.patch(makeDefaultIncidentStatusPath(id), {}, { preserveScroll: true })}
            defaultSelectable={stage.open}
            defaultHeaderHint="Every new incident starts in the default status. Only one can be the default at a time, so picking one here unselects it in the other stages."
            onToggleEnabled={(status) =>
              router.patch(
                status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={onEdit}
            onDelete={onDelete}
          />
        </CardContent>
      )}
    </Card>
  )
}
