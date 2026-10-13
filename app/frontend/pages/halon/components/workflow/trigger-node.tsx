import { Handle, type NodeProps, Position } from "@xyflow/react"
import { IconSparkles } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { OUT_HANDLE, STEP_WIDTH, type TriggerFlowNode } from "@/pages/halon/lib/workflow/canvas-graph"
import { TriggerIcon } from "@/pages/halon/components/workflow/trigger-icon"

// What starts a run, at the top of the canvas, with the inputs a person is asked when they run it by hand.
export function TriggerNode({ data }: NodeProps<TriggerFlowNode>) {
  const { trigger, halonMarked, selected, pending } = data
  const inputs = trigger.inputs.map((input) => input.key).join(", ")

  return (
    <div
      style={{ width: STEP_WIDTH }}
      className={cn(
        "relative rounded-md border border-border bg-surface-card px-3.5 py-3 transition-[border-color] duration-150 hover:border-border-strong",
        selected && "border-brand/60",
        halonMarked && "ring-2 ring-halon/70 ring-offset-2 ring-offset-background",
      )}
    >
      <div className="flex items-center gap-2.5">
        <TriggerIcon icon={trigger.icon} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13.5px] leading-tight font-semibold text-fg-headline">{trigger.label}</div>
          <div className="mt-0.5 truncate text-[11.5px] text-fg-muted">{inputs ? `Trigger · asks ${inputs}` : "Trigger"}</div>
        </div>
      </div>
      {pending.length > 0 && (
        <div className="mt-2.5 inline-flex h-5 items-center gap-1 rounded-full border border-halon-border bg-halon-tint px-2 text-[11px] text-halon">
          <IconSparkles className="size-3" />
          Halon suggests a change
        </div>
      )}
      <Handle id={OUT_HANDLE} type="source" position={Position.Bottom} className="!size-2 !min-h-0 !min-w-0 !border-0 !bg-transparent" isConnectable={false} />
    </div>
  )
}
