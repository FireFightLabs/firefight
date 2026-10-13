import { IconChevronRight, IconCornerDownRight } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_STEP_GROUP } from "@/lib/generated/constants"
import { RunState } from "@/pages/halon/components/workflow/run-state"
import { StepBadges } from "@/pages/halon/components/workflow/step-badges"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { SuggestionDecision } from "@/pages/halon/components/workflow/suggestion-decision"
import type { CanvasStep } from "@/pages/halon/lib/workflow/types"

interface StepListRowProps {
  item: CanvasStep
  depth: number
  // Where it leads, in words, or empty when it leads nowhere.
  leads: string
  halonMarked: boolean
  onPick: (stepId: string) => void
}

// One step in the phone's list: its icon, name, kind and badges, where it leads, and Accept and Dismiss for a step Halon
// suggests adding or removing.
export function StepListRow({ item, depth, leads, halonMarked, onPick }: StepListRowProps) {
  const removal = item.pending.find((each) => each.operation === WORKFLOW_EDIT_OPERATIONS.REMOVE_STEP) ?? null
  const decided = item.suggestion ?? removal

  function pick() {
    onPick(item.step.id)
  }

  return (
    <li style={{ marginLeft: depth * 16 }}>
      <div className={cn("border bg-surface-card", decided ? "border-dashed border-halon" : "border-border", halonMarked && "ring-2 ring-halon/70")}>
        <button type="button" onClick={pick} className="flex w-full items-center gap-3 px-3 py-3 text-left" disabled={item.suggestion !== null}>
          <StepIcon icon={item.step.icon} halon={item.step.group === WORKFLOW_STEP_GROUP.HALON} />
          <span className="min-w-0 flex-1 space-y-1">
            <span className={cn("block truncate text-sm font-semibold text-fg-headline", item.suggestion && "text-halon", removal && "line-through decoration-halon")}>
              {item.step.title}
            </span>
            <span className="block truncate text-xs text-fg-muted">{item.suggestion ? `Suggested · ${item.step.kindLabel}` : item.step.kindLabel}</span>
            <StepBadges item={item} />
            {item.state && <RunState state={item.state} />}
          </span>
          {!item.suggestion && <IconChevronRight className="size-4 shrink-0 text-fg-muted" />}
        </button>
        {leads && (
          <p className="flex items-center gap-1.5 border-t border-border px-3 py-1.5 text-[11.5px] text-fg-muted">
            <IconCornerDownRight className="size-3.5" />
            Then {leads}
          </p>
        )}
        {decided && (
          <div className="space-y-2 border-t border-halon-border px-3 py-2.5">
            {decided.reason && <p className="text-xs text-halon">{decided.reason}</p>}
            <SuggestionDecision suggestion={decided} acceptLabel={item.suggestion ? "Add step" : "Remove step"} />
          </div>
        )}
      </div>
    </li>
  )
}
