import type { CSSProperties, ReactNode } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical } from "@tabler/icons-react"

import type { ConfigurableOption } from "@/pages/settings/lib/types"
import { cn } from "@/lib/utils"
import { RadioGroupItem } from "@/components/ui/radio-group"
import { Switch } from "@/components/ui/switch"
import { TableCell, TableRow } from "@/components/ui/table"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { RowActions } from "@/pages/settings/components/row-actions"

// A disabled control swallows pointer events, so the tooltip rides on a span.
function Blocked({ reason, children }: { reason: string; children: ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-block">{children}</span>
      </TooltipTrigger>
      <TooltipContent side="left" className="max-w-56">{reason}</TooltipContent>
    </Tooltip>
  )
}

export function SortableOptionRow({
  option,
  fallbackColor,
  children,
  onToggleEnabled,
  onEdit,
  onDelete,
}: {
  option: ConfigurableOption
  fallbackColor?: string
  // Cells between the name and the Default column.
  children?: ReactNode
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
  } = useSortable({ id: option.id })

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
        !option.enabled && "opacity-50",
        isDragging && "relative bg-background shadow-lg",
      )}
    >
      <TableCell>
        <button
          ref={setActivatorNodeRef}
          type="button"
          className="flex cursor-grab touch-none items-center text-muted-foreground/50 transition-colors hover:text-muted-foreground active:cursor-grabbing"
          aria-label={`Reorder ${option.name}`}
          {...attributes}
          {...listeners}
        >
          <IconGripVertical className="size-4" />
        </button>
      </TableCell>

      <TableCell>
        <div className="flex items-center gap-2.5">
          <ColorDot color={option.color ?? fallbackColor ?? "#6B7280"} />
          <span className="font-medium">{option.name}</span>
        </div>
      </TableCell>

      {children}

      <TableCell className="text-center">
        {option.defaultBlockedReason ? (
          <Blocked reason={option.defaultBlockedReason}>
            <RadioGroupItem value={option.id} disabled aria-label={`${option.name} cannot be the default`} />
          </Blocked>
        ) : (
          <RadioGroupItem value={option.id} aria-label={`Make ${option.name} the default`} />
        )}
      </TableCell>

      <TableCell className="text-center">
        {option.disableBlockedReason ? (
          <Blocked reason={option.disableBlockedReason}>
            <Switch checked={option.enabled} disabled />
          </Blocked>
        ) : (
          <Switch checked={option.enabled} onCheckedChange={onToggleEnabled} />
        )}
      </TableCell>

      <TableCell>
        <RowActions
          onEdit={onEdit}
          onDelete={onDelete}
          deleteDisabledReason={option.deletionBlockedReason}
        />
      </TableCell>
    </TableRow>
  )
}
