import type { Page } from "@inertiajs/core"
import { router } from "@inertiajs/react"
import { useCallback } from "react"

import { WORKFLOW_CANVAS_PROPS, WORKFLOW_VERSION_STATUS } from "@/lib/generated/constants"
import { workflowEditsPath } from "@/lib/routes"
import type { JsonObject } from "@/lib/tool-fields"
import type { WorkflowDocument } from "@/types/serializers"

// Every change on the canvas reloads only what it can change, keeping the address, the open sheet and the tools list.
export const CANVAS_VISIT = {
  preserveScroll: true,
  preserveState: true,
  preserveUrl: true,
  only: [
    WORKFLOW_CANVAS_PROPS.WORKFLOW, WORKFLOW_CANVAS_PROPS.DOCUMENT, WORKFLOW_CANVAS_PROPS.VERSIONS, WORKFLOW_CANVAS_PROPS.SUGGESTIONS,
    WORKFLOW_CANVAS_PROPS.HALON_CHANGES, WORKFLOW_CANVAS_PROPS.PUBLISH_REQUESTS, WORKFLOW_CANVAS_PROPS.MY_PUBLISH_REQUEST,
  ],
}

// The draft revision a change was made on. A change to the live version opens a draft from it, so it names none.
export function revisionOf(document: WorkflowDocument): number | null {
  return document.saved && document.status === WORKFLOW_VERSION_STATUS.DRAFT ? document.revision : null
}

interface EditOptions {
  // The revision the person saw when they started, so a change someone made since to the same thing is refused.
  baseRevision?: number | null
  onSuccess?: () => void
}

export type SendEdit = (operation: string, payload: JsonObject, options?: EditOptions) => void

// Sends one change, a step added, moved, connected, set up or renamed, or the trigger changed, and the server says it
// happened or why not.
export function useWorkflowEdits(workflowId: string, document: WorkflowDocument): SendEdit {
  const current = revisionOf(document)
  return useCallback<SendEdit>((operation, payload, options = {}) => {
    const baseRevision = options.baseRevision === undefined ? current : options.baseRevision
    // A refused change redirects back too, with an alert, so only a change the server kept runs what follows it.
    function kept(page: Page) {
      if (!page.flash?.alert) {
        options.onSuccess?.()
      }
    }
    router.post(workflowEditsPath(workflowId), { operation, payload, base_revision: baseRevision }, { ...CANVAS_VISIT, onSuccess: kept })
  }, [ workflowId, current ])
}
