import { useContext } from "react"

import { type CanvasActions, CanvasActionsContext } from "@/pages/halon/lib/workflow/canvas-actions"

export function useCanvasActions(): CanvasActions {
  const actions = useContext(CanvasActionsContext)
  if (!actions) {
    throw new Error("useCanvasActions is used outside the workflow canvas")
  }
  return actions
}
