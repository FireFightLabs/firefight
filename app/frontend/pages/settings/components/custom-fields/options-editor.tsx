import type { CSSProperties } from "react"
import {
  closestCenter,
  DndContext,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core"
import { restrictToVerticalAxis } from "@dnd-kit/modifiers"
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical, IconPlus, IconTrash } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Blocked } from "@/pages/settings/components/blocked-tooltip"

// A row keeps its id across a rename, which is what stops a rename from
// orphaning the incidents pointing at it. Unsaved rows have no id yet.
export interface OptionDraft {
  key: string
  id?: string
  label: string
  disabled: boolean
  deletionBlockedReason?: string
}

export function duplicateLabels(options: OptionDraft[]) {
  const seen = options.map((option) => option.label.trim().toLowerCase())

  return new Set(seen.filter((label, index) => label.length > 0 && seen.indexOf(label) !== index))
}

export function hasDuplicateLabels(options: OptionDraft[]) {
  return duplicateLabels(options).size > 0
}

function SortableOption({
  option,
  onChange,
  onRemove,
}: {
  option: OptionDraft
  onChange: (patch: Partial<OptionDraft>) => void
  onRemove: () => void
}) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } =
    useSortable({ id: option.key })

  const style: CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition,
    zIndex: isDragging ? 10 : undefined,
  }

  const removeButton = (
    <Button
      type="button"
      variant="ghost"
      size="icon"
      className="size-8 text-muted-foreground"
      aria-label={`Delete ${option.label || "option"}`}
      disabled={Boolean(option.deletionBlockedReason)}
      onClick={onRemove}
    >
      <IconTrash className="size-4" />
    </Button>
  )

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn("flex items-center gap-2", option.disabled && "opacity-50")}
    >
      <button
        type="button"
        ref={setActivatorNodeRef}
        className="cursor-grab text-muted-foreground active:cursor-grabbing"
        aria-label={`Reorder ${option.label || "option"}`}
        {...attributes}
        {...listeners}
      >
        <IconGripVertical className="size-4" />
      </button>

      <Input
        value={option.label}
        maxLength={75}
        onChange={(event) => onChange({ label: event.target.value })}
        placeholder="Option label"
        className="flex-1"
      />

      <Switch
        checked={!option.disabled}
        aria-label={option.disabled ? `Enable ${option.label}` : `Disable ${option.label}`}
        onCheckedChange={(checked) => onChange({ disabled: !checked })}
      />

      <Blocked reason={option.deletionBlockedReason}>{removeButton}</Blocked>
    </div>
  )
}

export function OptionsEditor({
  options,
  onChange,
  error,
}: {
  options: OptionDraft[]
  onChange: (options: OptionDraft[]) => void
  error?: string
}) {
  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
  )

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) {
      return
    }

    const from = options.findIndex((option) => option.key === active.id)
    const to = options.findIndex((option) => option.key === over.id)
    if (from === -1 || to === -1) {
      return
    }

    const next = [ ...options ]
    const [ moved ] = next.splice(from, 1)
    next.splice(to, 0, moved)
    onChange(next)
  }

  const duplicates = duplicateLabels(options)

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <Label>Options</Label>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-8 gap-1.5 rounded-lg px-3 text-xs"
          onClick={() =>
            onChange([ ...options, { key: crypto.randomUUID(), label: "", disabled: false } ])
          }
        >
          <IconPlus className="size-3.5" />
          Add option
        </Button>
      </div>

      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        modifiers={[ restrictToVerticalAxis ]}
        onDragEnd={handleDragEnd}
      >
        <SortableContext items={options.map((option) => option.key)} strategy={verticalListSortingStrategy}>
          <div className="space-y-2">
            {options.map((option) => (
              <SortableOption
                key={option.key}
                option={option}
                onChange={(patch) =>
                  onChange(
                    options.map((current) =>
                      current.key === option.key ? { ...current, ...patch } : current
                    )
                  )
                }
                onRemove={() => onChange(options.filter((current) => current.key !== option.key))}
              />
            ))}
          </div>
        </SortableContext>
      </DndContext>

      {duplicates.size > 0 && (
        <p className="text-xs text-destructive">Option labels must be unique.</p>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
