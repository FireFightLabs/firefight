import { useState } from "react"
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

import type { IncidentSeveritySettings } from "@/types/serializers"
import {
  incidentSeverityPath,
  disableIncidentSeverityPath,
  enableIncidentSeverityPath,
  makeDefaultIncidentSeverityPath,
  reorderIncidentSeveritiesPath,
} from "@/lib/routes"
import { useDebouncedReorder } from "@/pages/settings/hooks/use-debounced-reorder"
import { RadioGroup } from "@/components/ui/radio-group"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AddSeverityDialog } from "@/pages/settings/components/severities/add-severity-dialog"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { EditSeverityDialog } from "@/pages/settings/components/severities/edit-severity-dialog"
import { SortableSeverityRow } from "@/pages/settings/components/severities/sortable-severity-row"

interface SeveritiesTabProps {
  severities: IncidentSeveritySettings[]
}

function incidentsInUse(count: number) {
  return `${count} ${count === 1 ? "incident" : "incidents"}`
}

export function SeveritiesTab({ severities: serverSeverities }: SeveritiesTabProps) {
  const { items: severities, onDragEnd } = useDebouncedReorder(serverSeverities, (orderedIds) => {
    router.patch(reorderIncidentSeveritiesPath(), { ordered_ids: orderedIds }, { preserveScroll: true })
  })

  const [editingSeverity, setEditingSeverity] = useState<IncidentSeveritySettings | null>(null)
  const [deletingSeverity, setDeletingSeverity] = useState<IncidentSeveritySettings | null>(null)

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))
  const defaultSeverityId = severities.find((severity) => severity.isDefault)?.id

  function handleToggleEnabled(severity: IncidentSeveritySettings) {
    router.patch(
      severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id)
    )
  }

  function handleMakeDefault(id: string) {
    router.patch(makeDefaultIncidentSeverityPath(id), {}, { preserveScroll: true })
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
              Define severity levels for classifying incident impact. Drag to reorder, most severe at the top.
            </CardDescription>
          </div>
          <AddSeverityDialog />
        </div>
      </CardHeader>
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
                <TableHead>Severity</TableHead>
                <TableHead className="hidden md:table-cell">Description</TableHead>
                <TableHead className="w-24 text-center">Default</TableHead>
                <TableHead className="w-24 text-center">Enabled</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <RadioGroup asChild className="table-row-group" value={defaultSeverityId} onValueChange={handleMakeDefault}>
              <TableBody>
                <SortableContext
                items={severities.map((severity) => severity.id)}
                strategy={verticalListSortingStrategy}
              >
                  {severities.map((severity) => (
                    <SortableSeverityRow
                      key={severity.id}
                      severity={severity}
                      deleteDisabledReason={deleteDisabledReason(severity)}
                      onToggleEnabled={() => handleToggleEnabled(severity)}
                      onEdit={() => setEditingSeverity(severity)}
                      onDelete={() => setDeletingSeverity(severity)}
                    />
                  ))}
                </SortableContext>
              </TableBody>
            </RadioGroup>
          </Table>
        </DndContext>
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
