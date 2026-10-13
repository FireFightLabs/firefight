import { IconChevronRight } from "@tabler/icons-react"

import { StepListRow } from "@/pages/halon/components/workflow/step-list-row"
import { TriggerIcon } from "@/pages/halon/components/workflow/trigger-icon"
import { canvasSteps } from "@/pages/halon/lib/workflow/canvas-graph"
import { routeWords } from "@/pages/halon/lib/workflow/labels"
import { stepsInOrder } from "@/pages/halon/lib/workflow/step-order"
import type { Selection, StepRunState } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDocument, WorkflowSuggestion } from "@/types/serializers"

interface StepListProps {
  document: WorkflowDocument
  suggestions: WorkflowSuggestion[]
  highlightHalon: boolean
  states?: Map<string, StepRunState>
  onSelect: (selection: Selection) => void
}

// The workflow on a phone: the trigger, then each step in the order it runs, the steps inside a for each indented under
// it, and where each leads. Tapping one opens the same settings the canvas does, since dragging a graph on a phone is not
// usable. Halon's suggested steps are in the list dashed, with Accept and Dismiss.
export function StepList({ document, suggestions, highlightHalon, states, onSelect }: StepListProps) {
  const ordered = stepsInOrder(canvasSteps(document.steps, suggestions, states), document.edges)
  const titles = new Map(document.steps.map((step) => [ step.id, step.title ]))

  function leadsTo(stepId: string): string {
    return document.edges.filter((edge) => edge.from === stepId)
      .map((edge) => (edge.route ? `${routeWords(edge.route)}: ${titles.get(edge.to) ?? "a step"}` : titles.get(edge.to) ?? "a step")).join(", ")
  }

  function pickTrigger() {
    onSelect({ kind: "trigger" })
  }

  function pickStep(stepId: string) {
    onSelect({ kind: "step", id: stepId })
  }

  return (
    <ol className="space-y-2 px-4 py-4">
      <li>
        <button type="button" onClick={pickTrigger} className="flex w-full items-center gap-3 border border-border bg-surface-card px-3 py-3 text-left">
          <TriggerIcon icon={document.trigger.icon} />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-semibold text-fg-headline">{document.trigger.label}</span>
            <span className="block text-xs text-fg-muted">Trigger</span>
          </span>
          <IconChevronRight className="size-4 text-fg-muted" />
        </button>
      </li>
      {ordered.map(({ item, depth }) => (
        <StepListRow
          key={item.step.id}
          item={item}
          depth={depth}
          leads={item.suggestion ? "" : leadsTo(item.step.id)}
          halonMarked={highlightHalon && item.step.changedByHalon}
          onPick={pickStep}
        />
      ))}
      {ordered.length === 0 && <li className="border border-dashed border-border px-4 py-6 text-center text-sm text-fg-muted">No steps yet. Add one to start.</li>}
    </ol>
  )
}
