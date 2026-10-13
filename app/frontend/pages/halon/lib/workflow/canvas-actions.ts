import { createContext } from "react"

import type { Edge } from "@/pages/halon/lib/workflow/types"

// What a node or an edge on the canvas can ask the page to do, so the drawing never sends a request of its own.
export interface CanvasActions {
  acceptSuggestion: (suggestionId: string) => void
  dismissSuggestion: (suggestionId: string) => void
  disconnect: (edge: Pick<Edge, "from" | "to" | "route" | "within">) => void
  select: (stepId: string) => void
}

export const CanvasActionsContext = createContext<CanvasActions | null>(null)
