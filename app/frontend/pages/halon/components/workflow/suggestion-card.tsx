import { IconSparkles } from "@tabler/icons-react"

import { SuggestionDecision } from "@/pages/halon/components/workflow/suggestion-decision"
import type { WorkflowSuggestion } from "@/types/serializers"

// One of Halon's suggestions in the settings sheet: what it would do and why, each field it would change with the old
// value struck through beside the new one, and Accept and Dismiss.
export function SuggestionCard({ suggestion }: { suggestion: WorkflowSuggestion }) {
  return (
    <div className="space-y-2 rounded-md border border-dashed border-halon bg-halon-tint/40 p-2.5">
      <div className="flex items-start gap-2">
        <IconSparkles className="mt-0.5 size-3.5 shrink-0 text-halon" />
        <div className="min-w-0 space-y-0.5">
          <p className="text-[12.5px] font-medium text-halon">{suggestion.words}</p>
          {suggestion.reason && <p className="text-xs leading-snug text-fg-secondary">{suggestion.reason}</p>}
        </div>
      </div>
      {suggestion.changes.length > 0 && (
        <dl className="space-y-1.5">
          {suggestion.changes.map((change) => (
            <div key={change.field} className="space-y-0.5">
              <dt className="text-[11px] text-fg-muted">{change.field}</dt>
              <dd className="flex flex-wrap items-baseline gap-x-2 font-mono text-xs [overflow-wrap:anywhere]">
                {change.before !== null && <del className="text-fg-muted decoration-halon">{change.before}</del>}
                <ins className="text-fg-primary no-underline">{change.after ?? "removed"}</ins>
              </dd>
            </div>
          ))}
        </dl>
      )}
      <SuggestionDecision suggestion={suggestion} />
    </div>
  )
}
