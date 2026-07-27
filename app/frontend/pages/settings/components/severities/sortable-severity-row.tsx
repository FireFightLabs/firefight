import type { CSSProperties } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical } from "@tabler/icons-react"

import type { IncidentSeveritySettings } from "@/types/serializers"
import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { TableCell, TableRow } from "@/components/ui/table"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { RowActions } from "@/pages/settings/components/row-actions"

export function SortableSeverityRow({
  severity,
  deleteDisabledReason,
  onToggleEnabled,
  onEdit,
  onDelete,
}: {
  severity: IncidentSeveritySettings
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
  } = useSortable({ id: severity.id })

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
        !severity.enabled && "opacity-50",
        isDragging && "relative bg-background shadow-lg",
      )}
    >
      <TableCell>
        <button
          ref={setActivatorNodeRef}
          type="button"
          className="flex cursor-grab touch-none items-center text-muted-foreground/50 transition-colors hover:text-muted-foreground active:cursor-grabbing"
          aria-label={`Reorder ${severity.name}`}
          {...attributes}
          {...listeners}
        >
          <IconGripVertical className="size-4" />
        </button>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2.5">
          <ColorDot color={severity.color} />
          <span className="font-medium">{severity.name}</span>
        </div>
      </TableCell>
      <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
        {severity.description}
      </TableCell>
      <TableCell className="text-center">
        {severity.isDefault && (
          <Badge variant="secondary" className="text-xs">
            Default
          </Badge>
        )}
      </TableCell>
      <TableCell className="text-center">
        <Switch
          checked={severity.enabled}
          disabled={severity.isDefault}
          onCheckedChange={onToggleEnabled}
        />
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
