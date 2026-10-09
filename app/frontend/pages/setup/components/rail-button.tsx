import { cn } from "@/lib/utils"
import { StepMarker } from "@/pages/setup/components/step-marker"
import { STATE_WORDS, STEP_TITLES, canOpen, type SetupStepKey } from "@/pages/setup/lib/steps"
import type { OnboardingStep } from "@/types/serializers"

interface RailButtonProps {
  step: OnboardingStep
  open: boolean
  number: number
  onOpen: (key: SetupStepKey) => void
}

// One step in the rail, its number or mark, its title and how far it got.
export function RailButton({ step, number, open, onOpen }: RailButtonProps) {
  const openable = canOpen(step)

  function openStep() {
    onOpen(step.key)
  }

  return (
    <button
      type="button"
      onClick={openStep}
      disabled={!openable}
      aria-current={open ? "step" : undefined}
      className={cn(
        "flex w-full items-center gap-3 rounded-md px-2.5 py-2 text-left transition-colors duration-150",
        open ? "edge-bar bg-surface-selected" : openable && "hover:bg-surface-hover",
        !openable && "cursor-default",
      )}
    >
      <StepMarker state={step.state} number={number} />
      <span className="flex min-w-0 flex-col">
        <span className={cn("truncate text-sm", openable ? "text-fg-primary" : "text-fg-muted")}>{STEP_TITLES[step.key]}</span>
        <span className="truncate text-xs text-fg-muted">{STATE_WORDS[step.state]}</span>
      </span>
    </button>
  )
}
