import * as React from "react"
import { router } from "@inertiajs/react"
import { incidentFormFieldPath, incidentFormFieldsPath } from "@/lib/routes"
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
  useSortable,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import {
  IconFilter,
  IconGripVertical,
  IconPlayerPlay,
  IconPlus,
  IconProgressCheck,
  IconRoute,
  IconSparkles,
  IconTrash,
  IconX,
} from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFieldDefinitionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/modules/settings/types"
import type { IncidentTypeSettings } from "@/types/serializers"
import { reorderIncidentFormFieldsPath } from "@/lib/routes"
import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"
import { Switch } from "@/components/ui/switch"

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


interface AddFieldDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  form: IncidentFormSettings
  availableFields: IncidentFieldDefinitionSettings[]
  allCustomFields: IncidentFieldDefinitionSettings[]
  onNavigateToCustomFields: () => void
}

function AddFieldDialog({ open, onOpenChange, form, availableFields, allCustomFields, onNavigateToCustomFields }: AddFieldDialogProps) {
  const [selectedFieldId, setSelectedFieldId] = React.useState(availableFields[0]?.id ?? "")

  React.useEffect(() => {
    setSelectedFieldId(availableFields[0]?.id ?? "")
  }, [availableFields, form.id])

  const attachedCustomFields = form.fields.filter((f) => f.fieldSourceKind === "custom")

  function handleSubmit() {
    if (!selectedFieldId) return

    router.post(incidentFormFieldsPath(), {
      incident_form_id: form.id,
      incident_field_definition_id: selectedFieldId,
    }, {
      preserveScroll: true,
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Add field to {form.name}</DialogTitle>
          <DialogDescription>
            Attach a reusable custom field to this lifecycle form.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {attachedCustomFields.length > 0 && (
            <div className="space-y-2">
              <Label className="text-xs text-muted-foreground">Already attached</Label>
              <div className="flex flex-wrap gap-1.5">
                {attachedCustomFields.map((f) => (
                  <Badge key={f.id} variant="secondary" className="text-xs">{f.name}</Badge>
                ))}
              </div>
            </div>
          )}

          {availableFields.length > 0 ? (
            <div className="space-y-2">
              <Label>Custom field</Label>
              <Select value={selectedFieldId} onValueChange={setSelectedFieldId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Select a field" />
                </SelectTrigger>
                <SelectContent>
                  {availableFields.map((field) => (
                    <SelectItem key={field.id} value={field.id}>
                      {field.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="rounded-xl border border-dashed border-border px-4 py-4 text-center text-sm text-muted-foreground">
              {allCustomFields.length === 0 ? (
                <div className="space-y-2">
                  <p>No custom fields defined yet.</p>
                  <Button
                    variant="link"
                    size="sm"
                    className="h-auto p-0 text-xs"
                    onClick={() => { onOpenChange(false); onNavigateToCustomFields() }}
                  >
                    Go to Custom Fields to create one
                  </Button>
                </div>
              ) : (
                <div className="space-y-2">
                <p>All custom fields are already attached to this form.</p>
                <Button
                  variant="link"
                  size="sm"
                  className="h-auto p-0 text-xs"
                  onClick={() => { onOpenChange(false); onNavigateToCustomFields() }}
                >
                  Create more in Custom Fields
                </Button>
              </div>
              )}
            </div>
          )}
        </div>

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline" type="button">Cancel</Button>
          </DialogClose>
          <Button onClick={handleSubmit} disabled={!selectedFieldId}>Add field</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

const CONDITION_FIELD_INCIDENT_TYPE = "incident_type"
const OPERATOR_ONE_OF = "one_of"
const OPERATOR_NOT_ONE_OF = "not_one_of"

const OPERATOR_LABELS: Record<string, string> = {
  [OPERATOR_ONE_OF]: "is one of",
  [OPERATOR_NOT_ONE_OF]: "is not one of",
}

function conditionSummary(conditions: IncidentConditionSettings[], incidentTypes: IncidentTypeSettings[]): string | null {
  if (!conditions.length) return null

  const typeMap = new Map(incidentTypes.map((t) => [t.id, t.name]))

  return conditions
    .map((c) => {
      const names = c.values.map((v) => typeMap.get(v) ?? v).join(", ")
      const label = OPERATOR_LABELS[c.operator] ?? c.operator
      return `Type ${label} ${names}`
    })
    .join("; ")
}

function ConditionEditor({ field, incidentTypes, onSave }: {
  field: IncidentFormFieldSettings
  incidentTypes: IncidentTypeSettings[]
  onSave: (conditions: IncidentConditionSettings[]) => void
}) {
  const existing = field.conditions?.[0]
  const [operator, setOperator] = React.useState(existing?.operator ?? OPERATOR_ONE_OF)
  const [selectedIds, setSelectedIds] = React.useState<Set<string>>(
    () => new Set(existing?.values ?? [])
  )
  const [open, setOpen] = React.useState(false)

  React.useEffect(() => {
    const current = field.conditions?.[0]
    setOperator(current?.operator ?? OPERATOR_ONE_OF)
    setSelectedIds(new Set(current?.values ?? []))
  }, [field.conditions])

  function toggleType(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function handleSave() {
    if (selectedIds.size === 0) {
      onSave([])
    } else {
      onSave([ {
        id: existing?.id ?? "",
        conditionField: CONDITION_FIELD_INCIDENT_TYPE,
        operator,
        values: Array.from(selectedIds),
      } ])
    }
    setOpen(false)
  }

  function handleClear() {
    onSave([])
    setOpen(false)
  }

  const hasConditions = (field.conditions?.length ?? 0) > 0

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className={cn(
            "flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] transition-colors",
            hasConditions
              ? "bg-cyan-500/10 text-cyan-600 dark:text-cyan-400 hover:bg-cyan-500/15"
              : "text-muted-foreground/50 hover:text-muted-foreground hover:bg-muted/30"
          )}
        >
          <IconFilter className="size-3" />
          {hasConditions
            ? conditionSummary(field.conditions!, incidentTypes)
            : "Add condition"}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 p-0">
        <div className="space-y-3 p-4">
          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Show this field when Incident Type</Label>
            <Select value={operator} onValueChange={setOperator}>
              <SelectTrigger className="h-8 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={OPERATOR_ONE_OF}>is one of</SelectItem>
                <SelectItem value={OPERATOR_NOT_ONE_OF}>is not one of</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs font-medium">Types</Label>
            <div className="max-h-48 space-y-1 overflow-y-auto rounded-md border border-border p-2">
              {incidentTypes.map((t) => (
                <label key={t.id} className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/30">
                  <Checkbox
                    checked={selectedIds.has(t.id)}
                    onCheckedChange={() => toggleType(t.id)}
                  />
                  <span>{t.name}</span>
                </label>
              ))}
              {incidentTypes.length === 0 && (
                <p className="py-2 text-center text-xs text-muted-foreground">No incident types defined.</p>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-border px-4 py-2.5">
          {hasConditions ? (
            <Button variant="ghost" size="sm" className="h-7 gap-1 px-2 text-xs text-muted-foreground hover:text-destructive" onClick={handleClear}>
              <IconX className="size-3" />
              Remove
            </Button>
          ) : (
            <div />
          )}
          <Button size="sm" className="h-7 px-3 text-xs" onClick={handleSave} disabled={selectedIds.size === 0 && !hasConditions}>
            Save
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  )
}


function SortableFieldRow({ field, incidentTypes, onUpdate, onUpdateConditions, onRemove }: {
  field: IncidentFormFieldSettings
  incidentTypes: IncidentTypeSettings[]
  onUpdate: (next: Partial<Pick<IncidentFormFieldSettings, "visibilityMode" | "requiredMode">>) => void
  onUpdateConditions: (conditions: IncidentConditionSettings[]) => void
  onRemove: () => void
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: field.id })

  const style: React.CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition,
    zIndex: isDragging ? 10 : undefined,
  }

  const isVisible = field.visibilityMode === "visible"
  const isRequired = field.requiredMode === "required" || field.lockedRequired
  const isSelect = [ "single_select", "multi_select", "catalog_reference", "catalog_multi_reference" ].includes(field.fieldType)

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn(
        "group border-b border-dashed border-border px-4 py-5 last:border-b-0",
        isDragging && "relative rounded-xl border-solid border-cyan-500/30 bg-background shadow-lg",
        !isVisible && "opacity-40",
      )}
    >
      {/* Field name + description + input preview */}
      <div className="flex items-start gap-2">
        <button
          ref={setActivatorNodeRef}
          type="button"
          className="mt-0.5 flex shrink-0 cursor-grab touch-none items-center text-muted-foreground/30 transition-colors hover:text-muted-foreground active:cursor-grabbing"
          {...attributes}
          {...listeners}
        >
          <IconGripVertical className="size-4" />
        </button>

        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="text-sm font-semibold">{field.name}</span>
            {isRequired && <span className="text-destructive">*</span>}
            {!isRequired && <span className="text-xs text-muted-foreground/50">(optional)</span>}
          </div>
          {field.description && (
            <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{field.description}</p>
          )}
          <div className="mt-2 max-w-lg">
            {isSelect ? (
              <div className="flex h-9 items-center rounded-md border border-border bg-muted px-3">
                <span className="flex-1 text-sm text-muted-foreground/50">Select an option...</span>
                <svg className="size-3.5 text-muted-foreground/30" viewBox="0 0 16 16" fill="none">
                  <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
            ) : field.key === "summary" ? (
              <div className="rounded-md border border-border bg-muted px-3 pt-2.5 pb-12">
                <span className="text-sm text-muted-foreground/50">Provide a summary...</span>
              </div>
            ) : (
              <div className="flex h-9 items-center rounded-md border border-border bg-muted px-3">
                <span className="text-sm text-muted-foreground/50">
                  {field.fieldType === "number" ? "0" : field.fieldType === "link" ? "https://..." : "Enter text..."}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Controls below the field content */}
      <div className="mt-3 flex items-center gap-4 pl-6">
        <label className="flex items-center gap-1.5 cursor-pointer">
          <span className="text-[11px] text-muted-foreground">Visible</span>
          <Switch
            checked={isVisible}
            disabled={field.lockedRequired}
            onCheckedChange={(checked) => onUpdate({ visibilityMode: checked ? "visible" : "hidden" })}
          />
        </label>

        <label className="flex items-center gap-1.5 cursor-pointer">
          <span className="text-[11px] text-muted-foreground">Required</span>
          {field.lockedRequired ? (
            <>
              <Switch checked disabled />
              <Badge variant="secondary" className="rounded-full px-1.5 py-0 text-[10px]">Locked</Badge>
            </>
          ) : (
            <Switch
              checked={field.requiredMode === "required"}
              onCheckedChange={(checked) => onUpdate({ requiredMode: checked ? "required" : "optional" })}
            />
          )}
        </label>

        {!field.lockedRequired && (
          <ConditionEditor
            field={field}
            incidentTypes={incidentTypes}
            onSave={onUpdateConditions}
          />
        )}

        {field.fieldSourceKind === "custom" && (
          <Button
            variant="ghost"
            size="sm"
            className="ml-auto h-6 gap-1 rounded-md px-2 text-[11px] text-muted-foreground/40 hover:text-destructive"
            onClick={onRemove}
          >
            <IconTrash className="size-3" />
            Remove
          </Button>
        )}
      </div>
    </div>
  )
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
  const selectedForm = React.useMemo(() => {
    return forms.find((form) => form.id === selectedFormId) ?? forms[0] ?? null
  }, [forms, selectedFormId])

  const [addFieldOpen, setAddFieldOpen] = React.useState(false)

  const availableFields = React.useMemo(() => {
    if (!selectedForm) return []
    const attachedIds = new Set(selectedForm.fields.map((field) => field.incidentFieldDefinitionId).filter(Boolean))
    return customFields.filter((field) => !attachedIds.has(field.id))
  }, [customFields, selectedForm])

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 5 },
    }),
  )

  const fieldIds = React.useMemo(
    () => selectedForm?.fields.map((f) => f.id) ?? [],
    [selectedForm?.fields],
  )

  const handleDragEnd = React.useCallback((event: DragEndEvent) => {
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
