import { useCallback, useLayoutEffect, useRef, useState } from "react"

interface PanelWidthOptions {
  storageKey: string
  defaultWidth: number
  minWidth: number
  // What the element beside the panel keeps however wide the panel is dragged.
  minRest: number
}

export interface PanelWidth {
  width: number
  min: number
  max: number
  panelRef: (element: HTMLElement | null) => void
  restRef: (element: HTMLElement | null) => void
  resize: (width: number) => void
  save: () => void
  reset: () => void
}

// Remembered per browser. Storage can be refused, in a private window for one, and then the panel opens at its default.
function readWidth(storageKey: string, fallback: number): number {
  try {
    const stored = Number(window.localStorage.getItem(storageKey))
    return Number.isFinite(stored) && stored > 0 ? stored : fallback
  } catch {
    return fallback
  }
}

function writeWidth(storageKey: string, width: number | null) {
  try {
    if (width === null) {
      window.localStorage.removeItem(storageKey)
    } else {
      window.localStorage.setItem(storageKey, String(Math.round(width)))
    }
  } catch {
    // Not remembered, the panel still takes the width for this visit.
  }
}

function clamp(width: number, min: number, max: number) {
  return Math.min(Math.max(width, min), max)
}

// A panel docked beside another element, as wide as the person last made it. The two share their room, so the panel
// grows only until the element beside it is down to minRest, and a narrower window narrows the panel without
// forgetting the width chosen.
export function usePanelWidth({ storageKey, defaultWidth, minWidth, minRest }: PanelWidthOptions): PanelWidth {
  const [ preferred, setPreferred ] = useState(() => readWidth(storageKey, defaultWidth))
  const [ room, setRoom ] = useState<number | null>(null)
  const [ panel, panelRef ] = useState<HTMLElement | null>(null)
  const [ rest, restRef ] = useState<HTMLElement | null>(null)
  const latest = useRef(preferred)

  useLayoutEffect(() => {
    if (!panel || !rest) {
      return
    }

    function measure() {
      if (panel && rest) {
        setRoom(panel.offsetWidth + rest.offsetWidth)
      }
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(panel)
    observer.observe(rest)
    return () => observer.disconnect()
  }, [ panel, rest ])

  const max = room === null ? Math.max(minWidth, preferred) : Math.max(minWidth, room - minRest)
  const width = clamp(preferred, minWidth, max)

  const resize = useCallback((next: number) => {
    const chosen = clamp(next, minWidth, max)
    latest.current = chosen
    setPreferred(chosen)
  }, [ minWidth, max ])

  const save = useCallback(() => {
    writeWidth(storageKey, latest.current)
  }, [ storageKey ])

  const reset = useCallback(() => {
    latest.current = defaultWidth
    setPreferred(defaultWidth)
    writeWidth(storageKey, null)
  }, [ storageKey, defaultWidth ])

  return { width, min: minWidth, max, panelRef, restRef, resize, save, reset }
}
