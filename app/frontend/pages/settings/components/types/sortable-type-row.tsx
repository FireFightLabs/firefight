import type { CSSProperties } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical } from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { RadioGroupItem } from "@/components/ui/radio-group"
import { Switch } from "@/components/ui/switch"
import { TableCell, TableRow } from "@/components/ui/table"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { RowActions } from "@/pages/settings/components/row-actions"

export function SortableTypeRow({
  type,
  deleteDisabledReason,
  onToggleEnabled,
  onEdit,
  onDelete,
}: {
  type: IncidentTypeSettings
  deleteDisabledReason?: string
  onToggleEnabled: () => void
  onEdit: () => void
  onDelete: () => void
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: type.id })

  const style: CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition,
    zIndex: isDragging ? 10 : undefined,
  }

  return (
    <TableRow
      ref={setNodeRef}
      style={style}
      className={cn(
        !type.enabled && "opacity-50",
        isDragging && "relative bg-background shadow-lg",
      )}
    >
      <TableCell>
        <button
          ref={setActivatorNodeRef}
          type="button"
          className="flex cursor-grab touch-none items-center text-muted-foreground/50 transition-colors hover:text-muted-foreground active:cursor-grabbing"
          aria-label={`Reorder ${type.name}`}
          {...attributes}
          {...listeners}
        >
          <IconGripVertical className="size-4" />
        </button>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2.5">
          <ColorDot color={type.color ?? "#6366F1"} />
          <span className="font-medium">{type.name}</span>
        </div>
      </TableCell>
      <TableCell className="hidden lg:table-cell">
        <span className="font-mono text-[12px] text-muted-foreground">{type.slug}</span>
      </TableCell>
      <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
        {type.description}
      </TableCell>
      <TableCell className="text-center">
        <Badge variant="outline" className="font-mono tabular-nums">
          {type.incidentCount}
        </Badge>
      </TableCell>
      <TableCell className="text-center">
        {type.enabled ? (
          <RadioGroupItem value={type.id} aria-label={`Make ${type.name} the default type`} />
        ) : (
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="inline-block">
                <RadioGroupItem value={type.id} disabled aria-label={`${type.name} is disabled`} />
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">
              A disabled type cannot be the default. Enable it first.
            </TooltipContent>
          </Tooltip>
        )}
      </TableCell>
      <TableCell className="text-center">
        {type.isDefault ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="inline-block">
                <Switch checked disabled />
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">
              The default type has to stay enabled. Make another type the default first.
            </TooltipContent>
          </Tooltip>
        ) : (
          <Switch checked={type.enabled} onCheckedChange={onToggleEnabled} />
        )}
      </TableCell>
      <TableCell>
        <RowActions
          onEdit={onEdit}
          onDelete={onDelete}
          deleteDisabledReason={deleteDisabledReason}
        />
      </TableCell>
    </TableRow>
  )
}
