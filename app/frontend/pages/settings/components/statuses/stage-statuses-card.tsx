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
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
} from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { HeaderHint } from "@/pages/settings/components/header-hint"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { DEFAULT_STATUS_HINT, slugColumnHint } from "@/pages/settings/lib/constants"

const stageColors: Record<string, string> = {
  triage: "border-stage-triage-border bg-stage-triage-tint text-stage-triage",
  active: "border-stage-active-border bg-stage-active-tint text-stage-active",
  closed: "border-stage-closed-border bg-stage-closed-tint text-stage-closed",
  canceled: "border-stage-canceled-border bg-stage-canceled-tint text-stage-canceled",
}

export function StageStatusesCard({
  stage,
  canManage,
  onCreate,
  onEdit,
  onDelete,
}: {
  stage: LifecycleStageWithStatuses
  canManage: boolean
  onCreate: (stage: LifecycleStageWithStatuses) => void
  onEdit: (status: IncidentStatusSettings) => void
  onDelete: (status: IncidentStatusSettings) => void
}) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-col items-start gap-2 sm:flex-row sm:items-center sm:gap-3">
            <span className={cn("inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium", stageColors[stage.key])}>{stage.name}</span>
            <CardDescription>{stage.description}</CardDescription>
          </div>
          {canManage && (
            <Button size="sm" variant="outline" onClick={() => onCreate(stage)}>
              <IconPlus className="size-4" />
              Add Status
            </Button>
          )}
        </div>
      </CardHeader>
      {stage.statuses.length > 0 && (
        <CardContent className="p-0">
          <OptionsTable
            options={stage.statuses}
            nameHeader="Status"
            headers={
              <>
                <TableHead className="hidden w-44 lg:table-cell">
                  <HeaderHint
                    label="Slug"
                    hint={slugColumnHint("status")}
                  />
                </TableHead>
                <TableHead className="hidden md:table-cell">Description</TableHead>
              </>
            }
            cells={(status) => (
              <>
                <TableCell className="hidden lg:table-cell">
                  <span className="font-mono text-[12px] text-muted-foreground">{status.slug}</span>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {status.description}
                </TableCell>
              </>
            )}
            reorderPath={reorderIncidentStatusesPath()}
            reorderParams={{ lifecycle_stage_key: stage.key }}
            fixedLayout
            onMakeDefault={(id) =>
              router.patch(makeDefaultIncidentStatusPath(id), {}, { preserveScroll: true })}
            defaultSelectable={stage.open}
            defaultHeaderHint={DEFAULT_STATUS_HINT}
            onToggleEnabled={(status) =>
              router.patch(
                status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={onEdit}
            onDelete={onDelete}
            readOnly={!canManage}
          />
        </CardContent>
      )}
    </Card>
  )
}
