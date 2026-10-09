import { useMemo, useState } from "react"
import { router } from "@inertiajs/react"
import { incidentFormFieldPath } from "@/lib/routes"
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
import {
  IconBan,
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
import type { IncidentSeveritySettings, IncidentStatusSettings, IncidentTypeSettings } from "@/types/serializers"
import { reorderIncidentFormFieldsPath } from "@/lib/routes"
import { useOptimisticOrder } from "@/hooks/use-optimistic-order"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { AddFieldDialog } from "@/pages/settings/components/forms/add-field-dialog"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { SortableFieldRow } from "@/pages/settings/components/forms/sortable-field-row"

function iconForForm(slug: string) {
  switch (slug) {
    case "declare":
      return <IconSparkles className="size-4" />
    case "resolve":
      return <IconProgressCheck className="size-4" />
    case "cancel":
      return <IconBan className="size-4" />
    default:
      return <IconRoute className="size-4" />
  }
}

function iconTintForForm(slug: string) {
  switch (slug) {
    case "declare":
      return "bg-error-tint text-error"
    case "resolve":
      return "bg-success-tint text-success"
    // The Canceled stage's grey, since cancelling is that stage.
    case "cancel":
      return "bg-stage-canceled-tint text-stage-canceled"
    default:
      return "bg-info-tint text-info"
  }
}

interface FormsTabProps {
  forms: IncidentFormSettings[]
  customFields: IncidentFieldDefinitionSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  statuses: IncidentStatusSettings[]
  selectedFormId: string | null
  canManage: boolean
  onSelectForm: (formId: string) => void
  onNavigateToCustomFields?: () => void
}

export function FormsTab({ forms, customFields, incidentTypes, severities, statuses, selectedFormId, canManage, onSelectForm, onNavigateToCustomFields }: FormsTabProps) {
  const selectedForm = useMemo(() => {
    return forms.find((form) => form.id === selectedFormId) ?? forms[0] ?? null
  }, [forms, selectedFormId])

  const [addFieldOpen, setAddFieldOpen] = useState(false)
  const [removing, setRemoving] = useState<IncidentFormFieldSettings | null>(null)

  const availableFields = useMemo(() => {
    if (!selectedForm) {
      return []
    }
    const attachedIds = new Set(selectedForm.fields.flatMap((field) => field.incidentFieldDefinitionId ? [field.incidentFieldDefinitionId] : []))
    return customFields.filter((field) => !attachedIds.has(field.id))
  }, [customFields, selectedForm])

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 5 },
    }),
  )

  const { ordered: orderedFields, onDragEnd } = useOptimisticOrder(selectedForm?.fields ?? [])

  function handleUpdateField(field: IncidentFormFieldSettings, next: Partial<Pick<IncidentFormFieldSettings, "visibilityMode" | "requiredMode">>) {
    // A default field has no row yet, so the form comes along for the backend
    // to materialize one.
    router.patch(incidentFormFieldPath(field.id), {
      incident_form_id: selectedForm?.id,
      visibility_mode: next.visibilityMode ?? field.visibilityMode,
      required_mode: next.requiredMode ?? field.requiredMode,
    }, {
      preserveScroll: true,
    })
  }

  // A default field has no row yet, so the form comes along for the backend to
  // materialize one. Returning early saved nothing and said nothing.
  function handleUpdateConditions(field: IncidentFormFieldSettings, conditions: IncidentConditionSettings[]) {
    router.patch(incidentFormFieldPath(field.id), {
      incident_form_id: selectedForm?.id,
      visibility_mode: field.visibilityMode,
      required_mode: field.requiredMode,
      conditions: conditions.map((condition) => ({
        condition_field: condition.conditionField,
        operator: condition.operator,
        values: condition.values,
        incident_field_definition_id: condition.incidentFieldDefinitionId,
      })),
    }, {
      preserveScroll: true,
    })
  }

  function confirmRemoveField() {
    if (!removing) {
      return
    }
    router.delete(incidentFormFieldPath(removing.id), {
      preserveScroll: true,
      onFinish: () => setRemoving(null),
    })
  }

  return (
    <div className="space-y-6">
      <div>
        <CardTitle>Forms</CardTitle>
        <CardDescription className="mt-1">
          Configure what responders see during declaration, updates, and resolution.
        </CardDescription>
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
                    ? "bg-surface-selected font-medium text-fg-primary"
                    : "text-fg-secondary hover:bg-surface-hover hover:text-fg-primary"
                )}
              >
                <span className={cn("rounded-md p-1", isSelected ? iconTintForForm(form.slug) : "text-fg-muted")}>
                  {iconForForm(form.slug)}
                </span>
                <span className="flex-1 truncate">{form.name}</span>
              </button>
            )
          })}
        </div>

        {selectedForm && (
          <Card className="overflow-hidden border-border">
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
                {canManage && (
                  <Button variant="outline" size="sm" className="h-8 gap-1.5 rounded-lg px-3 text-xs" onClick={() => setAddFieldOpen(true)}>
                    <IconPlus className="size-3.5" />
                    Add custom field
                  </Button>
                )}
              </div>
            </CardHeader>

            <CardContent className="p-0">
              <DndContext
                sensors={sensors}
                collisionDetection={closestCenter}
                modifiers={[restrictToVerticalAxis]}
                onDragEnd={(event) => onDragEnd(event, (orderedIds, onFailure) =>
                  router.patch(reorderIncidentFormFieldsPath(), {
                    incident_form_id: selectedForm.id,
                    ordered_ids: orderedIds,
                  }, { preserveScroll: true, onError: onFailure }))}
              >
                <SortableContext items={orderedFields.map((field) => field.id)} strategy={verticalListSortingStrategy}>
                  {orderedFields.map((field) => (
                    <SortableFieldRow
                      key={field.id}
                      form={selectedForm}
                      field={field}
                      incidentTypes={incidentTypes}
                      severities={severities}
                      statuses={statuses}
                      canManage={canManage}
                      onUpdate={(next) => handleUpdateField(field, next)}
                      onUpdateConditions={(conditions) => handleUpdateConditions(field, conditions)}
                      onRemove={() => setRemoving(field)}
                    />
                  ))}
                </SortableContext>
              </DndContext>
            </CardContent>
          </Card>
        )}
      </div>

      <ConfirmDeleteDialog
        open={Boolean(removing)}
        title={`Remove ${removing?.name ?? "this field"} from the form?`}
        description="The field definition itself is kept, so you can add it back at any time. Existing incidents keep the values they already have."
        confirmLabel="Remove"
        onConfirm={confirmRemoveField}
        onCancel={() => setRemoving(null)}
      />

      {selectedForm && canManage && (
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
