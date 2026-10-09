import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import { STATE_WORDS, STEP_TITLES, canOpen, type SetupStepKey } from "@/pages/setup/lib/steps"
import type { OnboardingStep } from "@/types/serializers"

const SEGMENT_TONES: Record<OnboardingStep["state"], string> = {
  [SETUP_STEP_STATES.DONE]: "bg-brand",
  [SETUP_STEP_STATES.SKIPPED]: "bg-brand",
  [SETUP_STEP_STATES.CURRENT]: "bg-fg-secondary",
  [SETUP_STEP_STATES.WAITING]: "bg-border-strong",
}

interface StepButtonProps {
  step: OnboardingStep
  open: boolean
  onOpen: (key: SetupStepKey) => void
}

// One step as a segment of the bar the rail becomes on a phone.
export function RailSegmentButton({ step, open, onOpen }: StepButtonProps) {
  function openStep() {
    onOpen(step.key)
  }

  return (
    <button
      type="button"
      onClick={openStep}
      disabled={!canOpen(step)}
      aria-label={`${STEP_TITLES[step.key]}, ${STATE_WORDS[step.state]}`}
      aria-current={open ? "step" : undefined}
      className={cn(
        "block h-1.5 w-full rounded-full transition-colors duration-150",
        SEGMENT_TONES[step.state],
        open && "outline-2 outline-offset-2 outline-brand",
      )}
    />
  )
}
