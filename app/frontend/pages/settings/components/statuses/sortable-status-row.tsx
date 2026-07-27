import type { CSSProperties } from "react"
import { useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { IconGripVertical } from "@tabler/icons-react"

import type { IncidentStatusSettings } from "@/types/serializers"
import { cn } from "@/lib/utils"
import { RadioGroupItem } from "@/components/ui/radio-group"
import { Switch } from "@/components/ui/switch"
import { TableCell, TableRow } from "@/components/ui/table"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { ColorDot } from "@/pages/settings/components/color-dot"
import { RowActions } from "@/pages/settings/components/row-actions"

export function SortableStatusRow({
  status,
  stageName,
  deleteDisabledReason,
  onToggleEnabled,
  onEdit,
  onDelete,
}: {
  status: IncidentStatusSettings
  stageName: string
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
  } = useSortable({ id: status.id })

  const style: CSSProperties = {
    transform: CSS.Translate.toString(transform),
    transition,
    zIndex: isDragging ? 10 : undefined,
  }

  function defaultBlockedReason() {
    if (status.isDefault) return undefined
    if (!status.enabled) return "A disabled status cannot be the default. Enable it first."
    if (!status.defaultable) {
      return `${stageName} statuses cannot be the default. A new incident has to start in triage or active.`
    }
    return undefined
  }

  function enabledBlockedReason() {
    if (status.isDefault) return "The default status has to stay enabled. Make another status the default first."
    if (status.lastEnabledInStage) return `This is the only enabled ${stageName} status. Add another one before disabling it.`
    return undefined
  }

  const defaultReason = defaultBlockedReason()
  const enabledReason = enabledBlockedReason()

  return (
    <TableRow
      ref={setNodeRef}
      style={style}
      className={cn(
        !status.enabled && "opacity-50",
        isDragging && "relative bg-background shadow-lg",
      )}
    >
      <TableCell>
        <button
          ref={setActivatorNodeRef}
          type="button"
          className="flex cursor-grab touch-none items-center text-muted-foreground/50 transition-colors hover:text-muted-foreground active:cursor-grabbing"
          aria-label={`Reorder ${status.name}`}
          {...attributes}
          {...listeners}
        >
          <IconGripVertical className="size-4" />
        </button>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2.5">
          <ColorDot color={status.color} />
          <span className="font-medium">{status.name}</span>
        </div>
      </TableCell>
      <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
        {status.description}
      </TableCell>
      <TableCell className="text-center">
        {defaultReason ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="inline-block">
                <RadioGroupItem value={status.id} disabled aria-label={`${status.name} cannot be the default`} />
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">{defaultReason}</TooltipContent>
          </Tooltip>
        ) : (
          <RadioGroupItem value={status.id} aria-label={`Make ${status.name} the default status`} />
        )}
      </TableCell>
      <TableCell className="text-center">
        {enabledReason ? (
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="inline-block">
                <Switch checked={status.enabled} disabled />
              </span>
            </TooltipTrigger>
            <TooltipContent side="left" className="max-w-56">{enabledReason}</TooltipContent>
          </Tooltip>
        ) : (
          <Switch checked={status.enabled} onCheckedChange={onToggleEnabled} />
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
