import { IconKey, IconSparkles } from "@tabler/icons-react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { cn } from "@/lib/utils"
import { WORKFLOW_STEP_EFFECT } from "@/lib/generated/constants"
import { EFFECT_LABELS } from "@/pages/halon/lib/workflow/labels"
import type { CanvasStep } from "@/pages/halon/lib/workflow/types"

const BADGE = "inline-flex h-5 items-center gap-1 rounded-full border px-2 text-[11px] font-medium leading-none whitespace-nowrap"

// What a step's line says beside its name: whether it reads or changes, whether the workflow's own identity needs a
// grant before it can run it, and that Halon suggests changing it.
export function StepBadges({ item }: { item: CanvasStep }) {
  const { step, pending } = item
  const changes = step.effect === WORKFLOW_STEP_EFFECT.CHANGES

  return (
    <span className="flex min-w-0 flex-wrap items-center gap-1.5">
      <span className={cn(BADGE, changes ? "border-warning-border bg-warning-tint text-warning" : "border-border-strong text-fg-secondary")}>
        {EFFECT_LABELS[step.effect]}
      </span>
      {step.grantNeeded && (
        <Tooltip>
          <TooltipTrigger asChild>
            <span className={cn(BADGE, "border-error-border bg-error-tint text-error")} tabIndex={0}>
              <IconKey className="size-3" />
              Needs grant
            </span>
          </TooltipTrigger>
          <TooltipContent className="max-w-64">{step.grantNeeded}</TooltipContent>
        </Tooltip>
      )}
      {!step.runnable && (
        <span className={cn(BADGE, "border-error-border bg-error-tint text-error")}>Cannot run here</span>
      )}
      {pending.length > 0 && (
        <span className={cn(BADGE, "border-halon-border bg-halon-tint text-halon")}>
          <IconSparkles className="size-3" />
          {pending.length === 1 ? "1 suggestion" : `${pending.length} suggestions`}
        </span>
      )}
    </span>
  )
}
