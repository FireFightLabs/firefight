import { IconCheck, IconMinus } from "@tabler/icons-react"

import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import type { OnboardingStep } from "@/types/serializers"

// A step's mark in the rail, a check once done, a dash once skipped, its number otherwise.
export function StepMarker({ state, number }: { state: OnboardingStep["state"]; number: number }) {
  const base = "flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-medium"
  if (state === SETUP_STEP_STATES.DONE) {
    return (
      <span className={cn(base, "bg-brand text-on-brand")}>
        <IconCheck className="size-3.5" stroke={3} />
      </span>
    )
  }
  if (state === SETUP_STEP_STATES.SKIPPED) {
    return (
      <span className={cn(base, "border border-border-strong text-fg-muted")}>
        <IconMinus className="size-3.5" />
      </span>
    )
  }

  return (
    <span className={cn(base, state === SETUP_STEP_STATES.CURRENT ? "border border-brand text-brand" : "border border-border-strong text-fg-muted")}>
      {number}
    </span>
  )
}
