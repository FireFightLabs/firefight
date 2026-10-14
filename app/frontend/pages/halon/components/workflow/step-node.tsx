import { Handle, type NodeProps, Position } from "@xyflow/react"

import { cn } from "@/lib/utils"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_STEP_GROUP } from "@/lib/generated/constants"
import { RouteHandles } from "@/pages/halon/components/workflow/route-handles"
import { RunState } from "@/pages/halon/components/workflow/run-state"
import { StepBadges } from "@/pages/halon/components/workflow/step-badges"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { SuggestionDecision } from "@/pages/halon/components/workflow/suggestion-decision"
import { IN_HANDLE, STEP_WIDTH, type StepFlowNode } from "@/pages/halon/lib/workflow/canvas-graph"

const IN_CLASS = "!size-2 !min-h-0 !min-w-0 !rounded-full !border !border-border-control !bg-surface-card"

// One step on the canvas: its kind's icon, its name, its kind, and whether it reads or changes. A step Halon suggests
// adding is dashed in violet with its reason, one Halon suggests removing is struck through, and each carries Accept
// and Dismiss. With Changes by Halon on, a step Halon last changed is ringed in violet.
export function StepNode({ data }: NodeProps<StepFlowNode>) {
  const { item, connected, halonMarked, selected, readOnly } = data
  const { step, suggestion, pending } = item
  const removal = pending.find((each) => each.operation === WORKFLOW_EDIT_OPERATIONS.REMOVE_STEP) ?? null
  const decided = suggestion ?? removal

  return (
    <div
      style={{ width: STEP_WIDTH }}
      className={cn(
        "group relative rounded-md border bg-surface-card px-3.5 pt-3 pb-3.5 transition-[border-color] duration-150",
        suggestion ? "border-dashed border-halon bg-halon-tint/40" : "border-border hover:border-border-strong",
        removal && "border-dashed border-halon opacity-80",
        selected && !suggestion && "border-brand/60",
        halonMarked && "ring-2 ring-halon/70 ring-offset-2 ring-offset-background",
      )}
      data-step={step.name}
    >
      <Handle id={IN_HANDLE} type="target" position={Position.Top} className={IN_CLASS} isConnectable={!readOnly} />
      <div className="flex items-center gap-2.5">
        <StepIcon icon={step.icon} halon={step.group === WORKFLOW_STEP_GROUP.HALON} />
        <div className="min-w-0 flex-1">
          <div className={cn("truncate text-[13.5px] leading-tight font-semibold text-fg-headline", suggestion && "text-halon", removal && "line-through decoration-halon")}>
            {step.title}
          </div>
          <div className="mt-0.5 truncate text-[11.5px] text-fg-muted">{suggestion ? `Suggested · ${step.kindLabel}` : step.kindLabel}</div>
        </div>
      </div>
      <div className="mt-2.5 flex items-center justify-between gap-2">
        <StepBadges item={item} />
        {item.state && <RunState state={item.state} />}
      </div>
      {decided && (
        <div className="mt-2.5 space-y-2">
          {decided.reason && <p className="text-xs leading-snug text-halon/90">{decided.reason}</p>}
          <SuggestionDecision suggestion={decided} acceptLabel={suggestion ? "Add step" : "Remove step"} disabled={readOnly && !suggestion} />
        </div>
      )}
      <RouteHandles routes={step.routes} labels={step.routeLabels} connected={connected} connectable={!readOnly} />
    </div>
  )
}
