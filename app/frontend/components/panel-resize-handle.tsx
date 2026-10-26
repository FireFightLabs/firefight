import { type KeyboardEvent, type PointerEvent, useRef, useState } from "react"

import type { PanelWidth } from "@/hooks/use-panel-width"
import { cn } from "@/lib/utils"

const STEP = 16
const LARGE_STEP = 64

interface PanelResizeHandleProps {
  panel: PanelWidth
  label: string
  // The id of the panel it resizes.
  controls: string
}

// The left edge of a panel docked on the right, from usePanelWidth. Dragging it left widens the panel, the arrow keys
// move it a step at a time (a larger one with Shift), Home and End go to the narrowest and widest, and a double click
// puts the panel back to its default width.
export function PanelResizeHandle({ panel, label, controls }: PanelResizeHandleProps) {
  const [ dragging, setDragging ] = useState(false)
  const start = useRef({ x: 0, width: 0 })

  function grab(event: PointerEvent<HTMLDivElement>) {
    if (event.button !== 0) {
      return
    }
    // Keeps the drag from selecting the text it passes over.
    event.preventDefault()
    event.currentTarget.setPointerCapture(event.pointerId)
    event.currentTarget.focus()
    start.current = { x: event.clientX, width: panel.width }
    setDragging(true)
  }

  function drag(event: PointerEvent<HTMLDivElement>) {
    if (dragging) {
      panel.resize(start.current.width + start.current.x - event.clientX)
    }
  }

  function release(event: PointerEvent<HTMLDivElement>) {
    if (!dragging) {
      return
    }
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
    setDragging(false)
    panel.save()
  }

  function press(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.shiftKey ? LARGE_STEP : STEP
    const widths: Record<string, number> = {
      ArrowLeft: panel.width + step,
      ArrowRight: panel.width - step,
      Home: panel.min,
      End: panel.max,
    }
    const next = widths[event.key]
    if (next === undefined) {
      return
    }
    event.preventDefault()
    panel.resize(next)
    panel.save()
  }

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label={label}
      aria-controls={controls}
      aria-valuenow={Math.round(panel.width)}
      aria-valuemin={Math.round(panel.min)}
      aria-valuemax={Math.round(panel.max)}
      tabIndex={0}
      data-dragging={dragging || undefined}
      onPointerDown={grab}
      onPointerMove={drag}
      onPointerUp={release}
      onPointerCancel={release}
      onLostPointerCapture={release}
      onKeyDown={press}
      onDoubleClick={panel.reset}
      className={cn(
        "absolute inset-y-0 -left-1 z-20 w-2 cursor-col-resize touch-none select-none",
        "after:absolute after:inset-y-0 after:left-1/2 after:w-0.5 after:-translate-x-1/2 hover:after:bg-border-control data-dragging:after:bg-border-control",
      )}
    />
  )
}
