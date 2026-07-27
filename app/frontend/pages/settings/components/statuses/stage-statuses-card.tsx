import { router } from "@inertiajs/react"
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import { restrictToVerticalAxis } from "@dnd-kit/modifiers"
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import {
  disableIncidentStatusPath,
  enableIncidentStatusPath,
  makeDefaultIncidentStatusPath,
  reorderIncidentStatusesPath,
} from "@/lib/routes"
import { useReorder } from "@/pages/settings/hooks/use-reorder"
import { Badge } from "@/components/ui/badge"
import { RadioGroup } from "@/components/ui/radio-group"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
} from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AddStatusDialog } from "@/pages/settings/components/statuses/add-status-dialog"
import { SortableStatusRow } from "@/pages/settings/components/statuses/sortable-status-row"

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

function incidentsInUse(count: number) {
  return `${count} ${count === 1 ? "incident" : "incidents"}`
}

// One card per lifecycle stage. Split out of the tab so each stage can hold its
// own drag context and radio group, which a hook cannot do from inside a map.
export function StageStatusesCard({
  stage,
  onEdit,
  onDelete,
}: {
  stage: LifecycleStageWithStatuses
  onEdit: (status: IncidentStatusSettings) => void
  onDelete: (status: IncidentStatusSettings) => void
}) {
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))

  const statuses = stage.statuses

  const { onDragEnd } = useReorder(statuses, (orderedIds) => {
    router.patch(reorderIncidentStatusesPath(), {
      lifecycle_stage_key: stage.key,
      ordered_ids: orderedIds,
    }, { preserveScroll: true })
  })

  function handleToggleEnabled(status: IncidentStatusSettings) {
    router.patch(
      status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id),
      {},
      { preserveScroll: true }
    )
  }

  function handleMakeDefault(id: string) {
    router.patch(makeDefaultIncidentStatusPath(id), {}, { preserveScroll: true })
  }

  function deleteDisabledReason(status: IncidentStatusSettings) {
    if (status.isDefault) return "This is the default status. Pick a new default before deleting it."
    if (status.incidentCount > 0) {
      return `In use by ${incidentsInUse(status.incidentCount)}. Disable it instead to keep it off new incidents.`
    }
    if (status.lastEnabledInStage) {
      return `This is the only enabled ${stage.name} status. Add another one before deleting it.`
    }
    return undefined
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Badge variant="secondary" className={stageColors[stage.key]}>
              {stage.name}
            </Badge>
            <CardDescription>{stage.description}</CardDescription>
          </div>
          <AddStatusDialog stage={stage} />
        </div>
      </CardHeader>
      {statuses.length > 0 && (
        <CardContent className="p-0">
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            modifiers={[ restrictToVerticalAxis ]}
            onDragEnd={onDragEnd}
          >
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
              <RadioGroup
                asChild
                className="table-row-group"
                value={statuses.find((status) => status.isDefault)?.id ?? ""}
                onValueChange={handleMakeDefault}
              >
                <TableBody>
                  <SortableContext
                    items={statuses.map((status) => status.id)}
                    strategy={verticalListSortingStrategy}
                  >
                    {statuses.map((status) => (
                      <SortableStatusRow
                        key={status.id}
                        status={status}
                        stageName={stage.name}
                        deleteDisabledReason={deleteDisabledReason(status)}
                        onToggleEnabled={() => handleToggleEnabled(status)}
                        onEdit={() => onEdit(status)}
                        onDelete={() => onDelete(status)}
                      />
                    ))}
                  </SortableContext>
                </TableBody>
              </RadioGroup>
            </Table>
          </DndContext>
        </CardContent>
      )}
    </Card>
  )
}
