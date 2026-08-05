import type { CSSProperties } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical, IconTrash } from "@tabler/icons-react"

import type {
  IncidentConditionSettings,
  IncidentFormFieldSettings,
  IncidentFormSettings,
} from "@/pages/settings/lib/types"
import type { IncidentSeveritySettings, IncidentStatusSettings, IncidentTypeSettings } from "@/types/serializers"
import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { ConditionEditor } from "@/pages/settings/components/forms/condition-editor"

export function SortableFieldRow({ field, form, incidentTypes, severities, statuses, onUpdate, onUpdateConditions, onRemove }: {
  field: IncidentFormFieldSettings
  form: IncidentFormSettings
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  statuses: IncidentStatusSettings[]
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

  const style: CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition,
    zIndex: isDragging ? 10 : undefined,
  }

  const isVisible = field.visibilityMode === "visible"
  const isRequired = field.requiredMode === "required" || field.lockedRequired
  const isSelect = [ "single_select", "multi_select", "catalog_reference", "catalog_multi_reference" ].includes(field.fieldType)
  const isMultiline = field.slug === "summary"
  // Falls back only for custom fields, which carry no placeholder of their own.
  const placeholder = field.placeholder ??
    (isSelect ? "Select an option..." : field.fieldType === "number" ? "0" : field.fieldType === "link" ? "https://..." : "Enter text...")

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
            <span className="text-sm font-semibold">{field.label}</span>
            {isRequired && <span className="text-destructive">*</span>}
            {!isRequired && <span className="text-xs text-muted-foreground/50">(optional)</span>}
          </div>
          {field.hint && (
            <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{field.hint}</p>
          )}
          {field.inactiveReason && (
            <p className="mt-1 text-xs italic leading-relaxed text-muted-foreground/70">{field.inactiveReason}</p>
          )}
          <div className="mt-2 max-w-lg">
            {isSelect ? (
              <div className="flex h-9 items-center rounded-md border border-border bg-muted px-3">
                <span className="flex-1 text-sm text-muted-foreground/50">{placeholder}</span>
                <svg className="size-3.5 text-muted-foreground/30" viewBox="0 0 16 16" fill="none">
                  <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
            ) : isMultiline ? (
              <div className="rounded-md border border-border bg-muted px-3 pt-2.5 pb-12">
                <span className="text-sm text-muted-foreground/50">{placeholder}</span>
              </div>
            ) : (
              <div className="flex h-9 items-center rounded-md border border-border bg-muted px-3">
                <span className="text-sm text-muted-foreground/50">{placeholder}</span>
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
            disabled={field.lockedVisible}
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
            form={form}
            incidentTypes={incidentTypes}
            severities={severities}
            statuses={statuses}
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
