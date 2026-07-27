import { useCallback, useState } from "react"
import { router } from "@inertiajs/react"
import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import type { DragEndEvent } from "@dnd-kit/core"
import { restrictToVerticalAxis } from "@dnd-kit/modifiers"
import {
  SortableContext,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import {
  incidentStatusPath,
  disableIncidentStatusPath,
  enableIncidentStatusPath,
  makeDefaultIncidentStatusPath,
  reorderIncidentStatusesPath,
} from "@/lib/routes"
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
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { EditStatusDialog } from "@/pages/settings/components/statuses/edit-status-dialog"
import { SortableStatusRow } from "@/pages/settings/components/statuses/sortable-status-row"

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

interface StatusesTabProps {
  lifecycleStages: LifecycleStageWithStatuses[]
}

function incidentsInUse(count: number) {
  return `${count} ${count === 1 ? "incident" : "incidents"}`
}

export function StatusesTab({ lifecycleStages }: StatusesTabProps) {
  const [editingStatus, setEditingStatus] = useState<IncidentStatusSettings | null>(null)
  const [deletingStatus, setDeletingStatus] = useState<IncidentStatusSettings | null>(null)

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))

  function handleToggleEnabled(status: IncidentStatusSettings) {
    router.patch(
      status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id)
    )
  }

  function handleMakeDefault(id: string) {
    router.patch(makeDefaultIncidentStatusPath(id), {}, { preserveScroll: true })
  }

  const handleDragEnd = useCallback((event: DragEndEvent, stage: LifecycleStageWithStatuses) => {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = stage.statuses.findIndex((s) => s.id === active.id)
    const newIndex = stage.statuses.findIndex((s) => s.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    const reordered = arrayMove(stage.statuses, oldIndex, newIndex)

    router.patch(reorderIncidentStatusesPath(), {
      lifecycle_stage_key: stage.key,
      ordered_ids: reordered.map((s) => s.id),
    }, {
      preserveScroll: true,
    })
  }, [])

  function confirmDelete() {
    if (!deletingStatus) return
    router.delete(incidentStatusPath(deletingStatus.id), {
      onFinish: () => setDeletingStatus(null),
    })
  }

  function deleteDisabledReason(status: IncidentStatusSettings, stageName: string) {
    if (status.isDefault) return "This is the default status. Pick a new default before deleting it."
    if (status.incidentCount > 0) {
      return `In use by ${incidentsInUse(status.incidentCount)}. Disable it instead to keep it off new incidents.`
    }
    if (status.lastEnabledInStage) {
      return `This is the only enabled ${stageName} status. Add another one before deleting it.`
    }
    return undefined
  }

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
        <Card key={stage.key}>
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
          {stage.statuses.length > 0 && (
            <CardContent className="p-0">
              <DndContext
                sensors={sensors}
                collisionDetection={closestCenter}
                modifiers={[ restrictToVerticalAxis ]}
                onDragEnd={(event) => handleDragEnd(event, stage)}
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
                    value={stage.statuses.find((status) => status.isDefault)?.id ?? ""}
                    onValueChange={handleMakeDefault}
                  >
                    <TableBody>
                      <SortableContext
                        items={stage.statuses.map((status) => status.id)}
                        strategy={verticalListSortingStrategy}
                      >
                        {stage.statuses.map((status) => (
                          <SortableStatusRow
                            key={status.id}
                            status={status}
                            stageName={stage.name}
                            deleteDisabledReason={deleteDisabledReason(status, stage.name)}
                            onToggleEnabled={() => handleToggleEnabled(status)}
                            onEdit={() => setEditingStatus(status)}
                            onDelete={() => setDeletingStatus(status)}
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
      ))}

      {editingStatus && (
        <EditStatusDialog
          status={editingStatus}
          open={!!editingStatus}
          onOpenChange={(open) => { if (!open) setEditingStatus(null) }}
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deletingStatus)}
        title={`Delete ${deletingStatus?.name ?? "this status"}?`}
        description="No incidents use this status, so nothing loses its history. It disappears from the status picker straight away."
        onConfirm={confirmDelete}
        onCancel={() => setDeletingStatus(null)}
      />
    </div>
  )
}
