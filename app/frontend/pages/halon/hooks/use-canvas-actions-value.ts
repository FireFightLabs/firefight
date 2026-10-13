import { router } from "@inertiajs/react"
import { useMemo } from "react"

import { WORKFLOW_EDIT_OPERATIONS } from "@/lib/generated/constants"
import { workflowSuggestionAcceptPath, workflowSuggestionDismissPath } from "@/lib/routes"
import { CANVAS_VISIT, type SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import type { CanvasActions } from "@/pages/halon/lib/workflow/canvas-actions"
import type { Selection } from "@/pages/halon/lib/workflow/types"

// What the canvas's nodes and connections may ask the page to do, each one request that the server answers with a toast.
export function useCanvasActionsValue(workflowId: string, send: SendEdit, onSelect: (selection: Selection) => void): CanvasActions {
  return useMemo(() => ({
    acceptSuggestion: (suggestionId: string) => router.post(workflowSuggestionAcceptPath(workflowId, suggestionId), {}, CANVAS_VISIT),
    dismissSuggestion: (suggestionId: string) => router.post(workflowSuggestionDismissPath(workflowId, suggestionId), {}, CANVAS_VISIT),
    disconnect: (edge) => {
      const payload = { from: edge.from, to: edge.to, route: edge.route }
      send(WORKFLOW_EDIT_OPERATIONS.DISCONNECT, edge.within ? { ...payload, within: edge.within } : payload)
    },
    select: (stepId: string) => onSelect({ kind: "step", id: stepId }),
  }), [ workflowId, send, onSelect ])
}
