import { useReactFlow, useViewport } from "@xyflow/react"
import { IconMaximize, IconMinus, IconPlus, IconSparkles } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

interface CanvasToolbarProps {
  highlightHalon: boolean
  onHighlightHalon: (on: boolean) => void
  // Further toggles a page adds, such as the last run's states.
  children?: ReactNode
}

const BUTTON = "flex size-7 items-center justify-center rounded-sm text-fg-secondary hover:bg-surface-hover hover:text-fg-primary"

// Zoom and fit for the canvas, and Changes by Halon, which rings what Halon last changed and lists its changes to undo.
export function CanvasToolbar({ highlightHalon, onHighlightHalon, children }: CanvasToolbarProps) {
  const { zoomIn, zoomOut, fitView } = useReactFlow()
  const { zoom } = useViewport()

  function zoomOutOnce() {
    zoomOut()
  }

  function zoomInOnce() {
    zoomIn()
  }

  function fit() {
    fitView({ padding: 0.2, maxZoom: 1 })
  }

  function toggleHalon() {
    onHighlightHalon(!highlightHalon)
  }

  return (
    <div className="flex items-center gap-0.5 rounded-sm border border-border bg-surface-card p-0.5">
      <button type="button" className={BUTTON} aria-label="Zoom out" onClick={zoomOutOnce}><IconMinus className="size-3.5" /></button>
      <span className="w-11 text-center text-[11.5px] text-fg-muted tabular-nums">{Math.round(zoom * 100)}%</span>
      <button type="button" className={BUTTON} aria-label="Zoom in" onClick={zoomInOnce}><IconPlus className="size-3.5" /></button>
      <button type="button" className={BUTTON} aria-label="Fit the workflow on screen" onClick={fit}><IconMaximize className="size-3.5" /></button>
      <span className="mx-0.5 h-5 w-px bg-border" />
      <button
        type="button"
        aria-pressed={highlightHalon}
        onClick={toggleHalon}
        className={cn("flex h-7 items-center gap-1.5 rounded-sm px-2 text-[11.5px] hover:bg-surface-hover", highlightHalon ? "text-halon" : "text-fg-secondary")}
      >
        <IconSparkles className="size-3.5" />
        Changes by Halon
      </button>
      {children}
    </div>
  )
}
