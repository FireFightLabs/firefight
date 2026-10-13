import { IconKey } from "@tabler/icons-react"
import type { DragEvent, ReactNode } from "react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { cn } from "@/lib/utils"

interface PaletteEntryProps {
  icon: ReactNode
  label: string
  description: string
  // Why the workflow's identity cannot use it yet, such as the grant a tool needs.
  grantNeeded?: string | null
  disabled: boolean
  // The data a drag carries, or nothing for an entry that cannot be dragged onto the canvas.
  dragData: string | null
  dragType: string
  onPick: () => void
}

// One thing the palette offers: a click adds it below the selected step, and a drag drops it where it is let go.
export function PaletteEntry({ icon, label, description, grantNeeded, disabled, dragData, dragType, onPick }: PaletteEntryProps) {
  function startDrag(event: DragEvent) {
    if (dragData) {
      event.dataTransfer.setData(dragType, dragData)
      event.dataTransfer.effectAllowed = "copy"
    }
  }

  return (
    <button
      type="button"
      draggable={!disabled && dragData !== null}
      disabled={disabled}
      onDragStart={startDrag}
      onClick={onPick}
      className={cn(
        "flex w-full items-center gap-2.5 rounded-sm px-2 py-1.5 text-left transition-colors hover:bg-surface-card disabled:pointer-events-none disabled:opacity-50",
        dragData && "cursor-grab active:cursor-grabbing",
      )}
    >
      {icon}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[12.5px] font-medium text-fg-primary">{label}</span>
        <span className="block truncate text-[11px] leading-snug text-fg-muted">{description}</span>
      </span>
      {grantNeeded && (
        <Tooltip>
          <TooltipTrigger asChild>
            <span className="text-error" aria-label={grantNeeded}>
              <IconKey className="size-3.5" />
            </span>
          </TooltipTrigger>
          <TooltipContent side="right" className="max-w-64">{grantNeeded}</TooltipContent>
        </Tooltip>
      )}
    </button>
  )
}
