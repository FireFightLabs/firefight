import { IconCheck, IconMinus } from "@tabler/icons-react"

import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import { STEP_TITLES, canOpen, type SetupStepKey } from "@/pages/setup/lib/steps"
import type { OnboardingStep } from "@/types/serializers"

type StepState = OnboardingStep["state"]

const STATE_WORDS: Record<StepState, string> = {
  [SETUP_STEP_STATES.DONE]: "Done",
  [SETUP_STEP_STATES.SKIPPED]: "Not now",
  [SETUP_STEP_STATES.CURRENT]: "Up next",
  [SETUP_STEP_STATES.WAITING]: "Waiting",
}

const SEGMENT_TONES: Record<StepState, string> = {
  [SETUP_STEP_STATES.DONE]: "bg-brand",
  [SETUP_STEP_STATES.SKIPPED]: "bg-brand",
  [SETUP_STEP_STATES.CURRENT]: "bg-fg-secondary",
  [SETUP_STEP_STATES.WAITING]: "bg-border-strong",
}

// Every step in order. A finished step or the one up next opens in the panel, a later one waits for those above it.
// On a phone the list becomes a bar of segments under a line saying where the person is.
export function SetupRail({
  steps,
  openKey,
  onOpen,
}: {
  steps: OnboardingStep[]
  openKey: SetupStepKey
  onOpen: (key: SetupStepKey) => void
}) {
  const done = steps.filter((step) => step.finished).length

  return (
    <nav aria-label="Setup steps" className="flex flex-col gap-3 md:sticky md:top-8 md:self-start">
      <p className="text-xs font-medium text-fg-muted">
        {done} of {steps.length} done
      </p>

      <ol className="flex gap-1.5 md:hidden">
        {steps.map((step) => (
          <li key={step.key} className="flex-1">
            <SegmentButton step={step} open={step.key === openKey} onOpen={onOpen} />
          </li>
        ))}
      </ol>

      <ol className="hidden flex-col gap-0.5 md:flex">
        {steps.map((step, index) => (
          <li key={step.key}>
            <RailButton step={step} number={index + 1} open={step.key === openKey} onOpen={onOpen} />
          </li>
        ))}
      </ol>
    </nav>
  )
}

interface StepButtonProps {
  step: OnboardingStep
  open: boolean
  onOpen: (key: SetupStepKey) => void
}

function SegmentButton({ step, open, onOpen }: StepButtonProps) {
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

function RailButton({ step, number, open, onOpen }: StepButtonProps & { number: number }) {
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

function StepMarker({ state, number }: { state: StepState; number: number }) {
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
