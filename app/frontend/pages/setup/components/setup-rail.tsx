import { RailButton } from "@/pages/setup/components/rail-button"
import { RailSegmentButton } from "@/pages/setup/components/rail-segment-button"
import type { SetupStepKey } from "@/pages/setup/lib/steps"
import type { OnboardingStep } from "@/types/serializers"

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
            <RailSegmentButton step={step} open={step.key === openKey} onOpen={onOpen} />
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
