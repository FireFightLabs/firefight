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
import {
  IconCategory,
  IconPlus,
} from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import {
  incidentTypePath,
  disableIncidentTypePath,
  enableIncidentTypePath,
  makeDefaultIncidentTypePath,
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
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { RadioGroup } from "@/components/ui/radio-group"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { SortableTypeRow } from "@/pages/settings/components/types/sortable-type-row"
import { TypeDialog } from "@/pages/settings/components/types/type-dialog"

interface TypesTabProps {
  types: IncidentTypeSettings[]
}

function incidentsInUse(count: number) {
  return `${count} ${count === 1 ? "incident" : "incidents"}`
}

export function TypesTab({ types }: TypesTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingType, setEditingType] = useState<IncidentTypeSettings | null>(null)
  const [deletingType, setDeletingType] = useState<IncidentTypeSettings | null>(null)

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }))
  const defaultTypeId = types.find((type) => type.isDefault)?.id

  function handleToggleEnabled(type: IncidentTypeSettings) {
    router.patch(
      type.enabled ? disableIncidentTypePath(type.id) : enableIncidentTypePath(type.id),
      {},
      { preserveScroll: true }
    )
  }

  function handleMakeDefault(id: string) {
    router.patch(makeDefaultIncidentTypePath(id), {}, { preserveScroll: true })
  }

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = types.findIndex((t) => t.id === active.id)
    const newIndex = types.findIndex((t) => t.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    const reordered = arrayMove(types, oldIndex, newIndex)

    router.patch(reorderIncidentTypesPath(), {
      ordered_ids: reordered.map((t) => t.id),
    }, {
      preserveScroll: true,
    })
  }, [types])

  function confirmDelete() {
    if (!deletingType) return
    router.delete(incidentTypePath(deletingType.id), {
      preserveScroll: true,
      onFinish: () => setDeletingType(null),
    })
  }

  function deleteDisabledReason(type: IncidentTypeSettings) {
    if (type.isDefault) return "This is the default type. Pick a new default before deleting it."
    if (!type.deletable) {
      return `In use by ${incidentsInUse(type.incidentCount)}. Disable it instead to keep it off new incidents.`
    }
    return undefined
  }

  function openCreate() {
    setEditingType(null)
    setDialogOpen(true)
  }

  function openEdit(type: IncidentTypeSettings) {
    setEditingType(type)
    setDialogOpen(true)
  }

  if (types.length === 0) {
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
            <Button size="sm" onClick={openCreate}>
              <IconPlus className="size-4" />
              Add type
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconCategory className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No incident types yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Create types like Outage, Degradation, or Security to classify incidents and drive type-specific workflows.
            </p>
            <Button size="sm" variant="outline" className="mt-4" onClick={openCreate}>
              <IconPlus className="size-3.5" />
              Create your first type
            </Button>
          </div>
        </CardContent>

        <TypeDialog
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          type={editingType}
        />
      </Card>
    )
  }

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
          <Button size="sm" onClick={openCreate}>
            <IconPlus className="size-4" />
            Add type
          </Button>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          modifiers={[ restrictToVerticalAxis ]}
          onDragEnd={handleDragEnd}
        >
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="w-8" />
                <TableHead>Type</TableHead>
                <TableHead className="hidden lg:table-cell">Slug</TableHead>
                <TableHead className="hidden md:table-cell">Description</TableHead>
                <TableHead className="w-28 text-center">Incidents</TableHead>
                <TableHead className="w-24 text-center">Default</TableHead>
                <TableHead className="w-24 text-center">Enabled</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <RadioGroup asChild className="table-row-group" value={defaultTypeId} onValueChange={handleMakeDefault}>
              <TableBody>
                <SortableContext
                  items={types.map((type) => type.id)}
                  strategy={verticalListSortingStrategy}
                >
                  {types.map((type) => (
                    <SortableTypeRow
                      key={type.id}
                      type={type}
                      deleteDisabledReason={deleteDisabledReason(type)}
                      onToggleEnabled={() => handleToggleEnabled(type)}
                      onEdit={() => openEdit(type)}
                      onDelete={() => setDeletingType(type)}
                    />
                  ))}
                </SortableContext>
              </TableBody>
            </RadioGroup>
          </Table>
        </DndContext>
      </CardContent>

      <TypeDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        type={editingType}
      />

      <ConfirmDeleteDialog
        open={Boolean(deletingType)}
        title={`Delete ${deletingType?.name ?? "this type"}?`}
        description="No incidents use this type, so nothing loses its history. It disappears from the declare form straight away."
        onConfirm={confirmDelete}
        onCancel={() => setDeletingType(null)}
      />
    </Card>
  )
}
