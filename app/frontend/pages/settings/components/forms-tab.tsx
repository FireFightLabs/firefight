import { useCallback, useMemo, useState } from "react"
import { router } from "@inertiajs/react"
import { incidentFormFieldPath } from "@/lib/routes"
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
  IconPlayerPlay,
  IconPlus,
  IconProgressCheck,
  IconRoute,
  IconSparkles,
} from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFieldDefinitionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/pages/settings/lib/types"
import type { IncidentTypeSettings } from "@/types/serializers"
import { reorderIncidentFormFieldsPath } from "@/lib/routes"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { AddFieldDialog } from "@/pages/settings/components/add-field-dialog"
import { SortableFieldRow } from "@/pages/settings/components/sortable-field-row"

function iconForForm(slug: string) {
  switch (slug) {
    case "declare":
      return <IconSparkles className="size-4" />
    case "accept":
      return <IconPlayerPlay className="size-4" />
    case "resolve":
      return <IconProgressCheck className="size-4" />
    default:
      return <IconRoute className="size-4" />
  }
}


function iconTintForForm(slug: string) {
  switch (slug) {
    case "declare":
      return "bg-rose-500/12 text-rose-700 dark:text-rose-300"
    case "accept":
      return "bg-violet-500/12 text-violet-700 dark:text-violet-300"
    case "resolve":
      return "bg-emerald-500/12 text-emerald-700 dark:text-emerald-300"
    default:
      return "bg-cyan-500/12 text-cyan-700 dark:text-cyan-300"
  }
}



interface FormsTabProps {
  forms: IncidentFormSettings[]
  customFields: IncidentFieldDefinitionSettings[]
  incidentTypes: IncidentTypeSettings[]
  selectedFormId: string | null
  onSelectForm: (formId: string) => void
  onNavigateToCustomFields?: () => void
}

export function FormsTab({ forms, customFields, incidentTypes, selectedFormId, onSelectForm, onNavigateToCustomFields }: FormsTabProps) {
  const selectedForm = useMemo(() => {
    return forms.find((form) => form.id === selectedFormId) ?? forms[0] ?? null
  }, [forms, selectedFormId])

  const [addFieldOpen, setAddFieldOpen] = useState(false)

  const availableFields = useMemo(() => {
    if (!selectedForm) return []
    const attachedIds = new Set(selectedForm.fields.map((field) => field.incidentFieldDefinitionId).filter(Boolean))
    return customFields.filter((field) => !attachedIds.has(field.id))
  }, [customFields, selectedForm])

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 5 },
    }),
  )

  const fieldIds = useMemo(
    () => selectedForm?.fields.map((f) => f.id) ?? [],
    [selectedForm?.fields],
  )

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    if (!selectedForm) return

    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = selectedForm.fields.findIndex((f) => f.id === active.id)
    const newIndex = selectedForm.fields.findIndex((f) => f.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    const reordered = arrayMove(selectedForm.fields, oldIndex, newIndex)

    router.patch(reorderIncidentFormFieldsPath(), {
      incident_form_id: selectedForm.id,
      ordered_ids: reordered.map((f) => f.id),
    }, {
      preserveScroll: true,
    })
  }, [selectedForm])

  function handleUpdateField(field: IncidentFormFieldSettings, next: Partial<Pick<IncidentFormFieldSettings, "visibilityMode" | "requiredMode">>) {
    router.patch(incidentFormFieldPath(field.id), {
      visibility_mode: next.visibilityMode ?? field.visibilityMode,
      required_mode: next.requiredMode ?? field.requiredMode,
    }, {
      preserveScroll: true,
    })
  }

  function handleUpdateConditions(field: IncidentFormFieldSettings, conditions: IncidentConditionSettings[]) {
    router.patch(incidentFormFieldPath(field.id), {
      visibility_mode: field.visibilityMode,
      required_mode: field.requiredMode,
      conditions: conditions.map((c) => ({
        condition_field: c.conditionField,
        operator: c.operator,
        values: c.values,
      })),
    }, {
      preserveScroll: true,
    })
  }

  function handleRemoveField(field: IncidentFormFieldSettings) {
    router.delete(incidentFormFieldPath(field.id), { preserveScroll: true })
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold tracking-tight">Forms</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Configure what responders see during declaration, updates, and resolution.
        </p>
      </div>

      <div className="grid gap-5 xl:grid-cols-[200px_minmax(0,1fr)]">
        <div className="flex flex-col gap-1 self-start rounded-xl border border-border bg-muted p-1.5">
          {forms.map((form) => {
            const isSelected = selectedForm?.id === form.id

            return (
              <button
                key={form.id}
                type="button"
                onClick={() => onSelectForm(form.id)}
                className={cn(
                  "flex items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm transition-colors",
                  isSelected
                    ? "bg-background font-medium text-foreground shadow-sm"
                    : "text-muted-foreground hover:bg-background/60 hover:text-foreground"
                )}
              >
                <span className={cn("rounded-md p-1", isSelected ? iconTintForForm(form.slug) : "text-muted-foreground/60")}>
                  {iconForForm(form.slug)}
                </span>
                <span className="flex-1 truncate">{form.name}</span>
                <span className="text-xs tabular-nums text-muted-foreground/60">{form.fieldCount}</span>
              </button>
            )
          })}
        </div>

        {selectedForm && (
          <Card className="overflow-hidden border-border shadow-[0_26px_80px_-52px_rgba(8,15,30,0.32)]">
            <CardHeader className="border-b border-border px-5 py-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <span className={cn("rounded-md p-1", iconTintForForm(selectedForm.slug))}>
                    {iconForForm(selectedForm.slug)}
                  </span>
                  <div>
                    <CardTitle className="text-sm font-semibold">{selectedForm.name}</CardTitle>
                    <CardDescription className="text-xs">{selectedForm.description}</CardDescription>
                  </div>
                </div>
                <Button variant="outline" size="sm" className="h-8 gap-1.5 rounded-lg px-3 text-xs" onClick={() => setAddFieldOpen(true)}>
                  <IconPlus className="size-3.5" />
                  Add custom field
                </Button>
              </div>
            </CardHeader>

            <CardContent className="p-0">
              <DndContext
                sensors={sensors}
                collisionDetection={closestCenter}
                modifiers={[restrictToVerticalAxis]}
                onDragEnd={handleDragEnd}
              >
                <SortableContext items={fieldIds} strategy={verticalListSortingStrategy}>
                  {selectedForm.fields.map((field) => (
                    <SortableFieldRow
                      key={field.id}
                      field={field}
                      incidentTypes={incidentTypes}
                      onUpdate={(next) => handleUpdateField(field, next)}
                      onUpdateConditions={(conditions) => handleUpdateConditions(field, conditions)}
                      onRemove={() => handleRemoveField(field)}
                    />
                  ))}
                </SortableContext>
              </DndContext>
            </CardContent>
          </Card>
        )}
      </div>

      {selectedForm && (
        <AddFieldDialog
          open={addFieldOpen}
          onOpenChange={setAddFieldOpen}
          form={selectedForm}
          availableFields={availableFields}
          allCustomFields={customFields}
          onNavigateToCustomFields={onNavigateToCustomFields ?? (() => {})}
        />
      )}
    </div>
  )
}
