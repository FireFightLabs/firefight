import { Link, router } from "@inertiajs/react"
import { IconSparkles } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { workflowSuggestionsAcceptPath, workflowSuggestionsDismissPath } from "@/lib/routes"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowSuggestion } from "@/types/serializers"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"

// How many of Halon's suggestions wait and where they came from, with Accept all and Dismiss all. Each is also on the
// canvas, to decide one at a time.
export function SuggestionsBanner({ workflowId, suggestions }: { workflowId: string; suggestions: WorkflowSuggestion[] }) {
  const canEdit = useWorkflowAccess().build
  const source = suggestions.find((suggestion) => suggestion.sourceLabel) ?? null
  const count = suggestions.length === 1 ? "1 suggestion" : `${suggestions.length} suggestions`

  function acceptAll() {
    router.post(workflowSuggestionsAcceptPath(workflowId), {}, CANVAS_VISIT)
  }

  function dismissAll() {
    router.post(workflowSuggestionsDismissPath(workflowId), {}, CANVAS_VISIT)
  }

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-halon-border bg-halon-tint/50 px-4 py-2 edge-bar [--edge-bar:var(--halon)]">
      <IconSparkles className="size-4 shrink-0 text-halon" />
      <p className="min-w-0 flex-1 text-[13px] text-fg-primary">
        {count} from Halon
        {source?.sourceLabel && (
          <>
            {", from "}
            {source.sourceHref ? <Link href={source.sourceHref} className="text-halon underline-offset-2 hover:underline">{source.sourceLabel}</Link> : source.sourceLabel}
          </>
        )}
        . Each is dashed or struck on the canvas.
      </p>
      {canEdit && (
        <div className="flex gap-2">
          <Button type="button" size="sm" variant="outline" className="h-7 text-xs" onClick={dismissAll}>Dismiss all</Button>
          <Button type="button" size="sm" className="h-7 bg-brand text-xs text-on-brand hover:bg-brand-hover" onClick={acceptAll}>Accept all</Button>
        </div>
      )}
    </div>
  )
}
