import { IconUserCheck } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { STEP_STATUS_LABELS, STEP_STATUS_TONES } from "@/pages/halon/lib/workflow/run-states"
import type { StepRunState } from "@/pages/halon/lib/workflow/types"

// How a step stood in the run shown: a dot and its time or state in the state's colour, and Waiting approval when an
// approval rule holds what it called.
export function RunState({ state }: { state: StepRunState }) {
  return (
    <span className="flex items-center gap-1.5">
      {state.waitingApproval && (
        <span className="inline-flex h-5 items-center gap-1 rounded-full border border-warning-border bg-warning-tint px-2 text-[11px] font-medium text-warning">
          <IconUserCheck className="size-3" />
          Waiting approval
        </span>
      )}
      <span className={cn("inline-flex items-center gap-1.5 font-mono text-[10.5px]", STEP_STATUS_TONES[state.status])} title={STEP_STATUS_LABELS[state.status]}>
        <span className="size-1.5 rounded-full bg-current" />
        {state.label}
      </span>
    </span>
  )
}
