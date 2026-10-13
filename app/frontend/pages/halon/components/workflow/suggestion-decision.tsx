import type { MouseEvent } from "react"

import { Button } from "@/components/ui/button"
import { useCanvasActions } from "@/pages/halon/hooks/use-canvas-actions"
import type { WorkflowSuggestion } from "@/types/serializers"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"

// Accept and Dismiss for one suggestion of Halon's, on its node, its connection or in the settings sheet.
export function SuggestionDecision({ suggestion, acceptLabel = "Accept", disabled = false }: { suggestion: WorkflowSuggestion; acceptLabel?: string; disabled?: boolean }) {
  const { acceptSuggestion, dismissSuggestion } = useCanvasActions()
  const canEdit = useWorkflowAccess().build
  const off = disabled || !canEdit

  function accept(event: MouseEvent) {
    event.stopPropagation()
    acceptSuggestion(suggestion.id)
  }

  function dismiss(event: MouseEvent) {
    event.stopPropagation()
    dismissSuggestion(suggestion.id)
  }

  return (
    <div className="nodrag flex gap-1.5">
      <Button type="button" size="sm" className="h-7 bg-brand px-2.5 text-xs text-on-brand hover:bg-brand-hover" disabled={off} onClick={accept}>
        {acceptLabel}
      </Button>
      <Button type="button" size="sm" variant="outline" className="h-7 px-2.5 text-xs" disabled={off} onClick={dismiss}>
        Dismiss
      </Button>
    </div>
  )
}
