import * as React from "react"
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
  useSortable,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import {
  IconChecklist,
  IconGripVertical,
  IconPlayerPlay,
  IconPlus,
  IconProgressCheck,
  IconRoute,
  IconSparkles,
  IconTrash,
} from "@tabler/icons-react"

import type {
  IncidentFieldDefinitionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/modules/settings/types"
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

function accentForForm(slug: string) {
  switch (slug) {
    case "declare":
      return "from-rose-500/16 via-orange-400/8 to-transparent"
    case "accept":
      return "from-violet-500/16 via-indigo-400/8 to-transparent"
    case "resolve":
      return "from-emerald-500/16 via-cyan-400/8 to-transparent"
    default:
      return "from-cyan-500/16 via-sky-400/8 to-transparent"
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

function titleCase(value: string) {
  return value.split("_").map((part) => part[0]?.toUpperCase() + part.slice(1)).join(" ")
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

    router.post("/app/settings/forms/fields", {
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
            <div className="rounded-xl border border-dashed border-border/60 px-4 py-4 text-center text-sm text-muted-foreground">
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

function SortableFieldRow({ field, onUpdate, onRemove }: {
  field: IncidentFormFieldSettings
  onUpdate: (next: Partial<Pick<IncidentFormFieldSettings, "visibilityMode" | "requiredMode">>) => void
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
        "group border-b border-dashed border-border/40 px-4 py-5 last:border-b-0",
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
              <div className="flex h-9 items-center rounded-md border border-border/60 bg-muted/15 px-3">
                <span className="flex-1 text-sm text-muted-foreground/50">Select an option...</span>
                <svg className="size-3.5 text-muted-foreground/30" viewBox="0 0 16 16" fill="none">
                  <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
            ) : field.key === "summary" ? (
              <div className="rounded-md border border-border/60 bg-muted/15 px-3 pt-2.5 pb-12">
                <span className="text-sm text-muted-foreground/50">Provide a summary...</span>
              </div>
            ) : (
              <div className="flex h-9 items-center rounded-md border border-border/60 bg-muted/15 px-3">
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
  selectedFormId: string | null
  onSelectForm: (formId: string) => void
  onNavigateToCustomFields?: () => void
}

export function FormsTab({ forms, customFields, selectedFormId, onSelectForm, onNavigateToCustomFields }: FormsTabProps) {
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
    router.patch(`/app/settings/forms/fields/${field.id}`, {
      visibility_mode: next.visibilityMode ?? field.visibilityMode,
      required_mode: next.requiredMode ?? field.requiredMode,
    }, {
      preserveScroll: true,
    })
  }

  function handleRemoveField(field: IncidentFormFieldSettings) {
    router.delete(`/app/settings/forms/fields/${field.id}`, { preserveScroll: true })
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
        <div className="flex flex-col gap-1 self-start rounded-xl border border-border/50 bg-muted/20 p-1.5">
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
          <Card className="overflow-hidden border-border/70 shadow-[0_26px_80px_-52px_rgba(8,15,30,0.32)]">
            <CardHeader className="border-b border-border/50 px-5 py-4">
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
                      onUpdate={(next) => handleUpdateField(field, next)}
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
