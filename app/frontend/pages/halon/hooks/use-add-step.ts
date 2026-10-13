import { useCallback } from "react"

import { WORKFLOW_EDIT_OPERATIONS } from "@/lib/generated/constants"
import type { SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import { STEP_HEIGHT } from "@/pages/halon/lib/workflow/canvas-graph"
import { newStep, type PaletteChoice } from "@/pages/halon/lib/workflow/new-step"
import type { WorkflowDocument } from "@/types/serializers"

const GAP_BELOW = 72

export interface AddAt {
  position?: { x: number; y: number }
  within?: string | null
}

// Adds a step from the palette where it was dropped, or below the step selected and connected to it when it was
// clicked, so building a straight run of steps is a click each. A step with routes is left for the person to connect,
// since which route leads on is theirs to say. Opens the new step's settings once it is there.
export function useAddStep(document: WorkflowDocument, send: SendEdit, selectedId: string | null, onAdded: (stepId: string) => void) {
  return useCallback((choice: PaletteChoice, at: AddAt = {}) => {
    const selected = document.steps.find((step) => step.id === selectedId) ?? null
    const topLevel = document.steps.filter((step) => !step.within)
    const last = topLevel[topLevel.length - 1] ?? null
    const anchor = at.position ? null : selected ?? last
    const position = at.position ?? (anchor?.position ? { x: anchor.position.x, y: anchor.position.y + STEP_HEIGHT + GAP_BELOW } : null)
    const within = at.position ? at.within ?? null : anchor?.within ?? null
    const step = newStep(choice, document, position)
    const payload = within ? { step, within } : { step }
    const connectFrom = anchor && anchor.routes.length === 0 && at.position === undefined ? anchor : null

    send(WORKFLOW_EDIT_OPERATIONS.ADD_STEP, payload, {
      onSuccess: () => {
        onAdded(String(step.id))
        if (connectFrom) {
          const edge = { from: connectFrom.id, to: String(step.id) }
          send(WORKFLOW_EDIT_OPERATIONS.CONNECT, within ? { ...edge, within } : edge, { baseRevision: null })
        }
      },
    })
  }, [ document, send, selectedId, onAdded ])
}
