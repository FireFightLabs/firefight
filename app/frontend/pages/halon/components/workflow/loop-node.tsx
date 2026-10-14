import { Handle, type NodeProps, Position } from "@xyflow/react"

import { cn } from "@/lib/utils"
import { WORKFLOW_CONFIG_KEYS, WORKFLOW_EDIT_OPERATIONS } from "@/lib/generated/constants"
import { RouteHandles } from "@/pages/halon/components/workflow/route-handles"
import { RunState } from "@/pages/halon/components/workflow/run-state"
import { StepBadges } from "@/pages/halon/components/workflow/step-badges"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { SuggestionDecision } from "@/pages/halon/components/workflow/suggestion-decision"
import { IN_HANDLE, type LoopFlowNode } from "@/pages/halon/lib/workflow/canvas-graph"

// A for each, drawn as a box around the steps it runs once for each item, headed by its name and what it goes through.
export function LoopNode({ data }: NodeProps<LoopFlowNode>) {
  const { item, connected, width, height, halonMarked, selected, readOnly } = data
  const { step, suggestion, pending } = item
  const removal = pending.find((each) => each.operation === WORKFLOW_EDIT_OPERATIONS.REMOVE_STEP) ?? null
  const decided = suggestion ?? removal
  const listed = step.config[WORKFLOW_CONFIG_KEYS.ITEMS]
  const items = typeof listed === "string" ? listed : ""

  return (
    <div
      style={{ width, height }}
      className={cn(
        "relative rounded-lg border bg-surface-card/40",
        suggestion || removal ? "border-dashed border-halon" : "border-border-strong",
        selected && !suggestion && "border-brand/60",
        halonMarked && "ring-2 ring-halon/70 ring-offset-2 ring-offset-background",
      )}
    >
      <Handle id={IN_HANDLE} type="target" position={Position.Top} className="!size-2 !min-h-0 !min-w-0 !rounded-full !border !border-border-control !bg-surface-card" isConnectable={!readOnly} />
      <div className="flex items-center gap-2.5 border-b border-border px-3.5 py-2.5">
        <StepIcon icon={step.icon} size="sm" />
        <div className="min-w-0 flex-1">
          <div className={cn("truncate text-[13px] font-semibold text-fg-headline", removal && "line-through decoration-halon")}>{step.title}</div>
          <div className="truncate font-mono text-[11px] text-fg-muted">{items ? `For each of ${items}` : "For each item of a list"}</div>
        </div>
        <StepBadges item={item} />
        {item.state && <RunState state={item.state} />}
      </div>
      {decided && (
        <div className="absolute top-full mt-2 flex items-center gap-2">
          <SuggestionDecision suggestion={decided} acceptLabel={suggestion ? "Add step" : "Remove step"} />
        </div>
      )}
      <RouteHandles routes={step.routes} labels={step.routeLabels} connected={connected} connectable={!readOnly} />
    </div>
  )
}
