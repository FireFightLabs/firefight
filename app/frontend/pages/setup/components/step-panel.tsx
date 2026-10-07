import type { ReactNode } from "react"

import { SETUP_STEPS } from "@/lib/generated/constants"
import { AccountStep } from "@/pages/setup/components/account-step"
import { AiStep } from "@/pages/setup/components/ai-step"
import { HalonStep } from "@/pages/setup/components/halon-step"
import { PermissionsStep } from "@/pages/setup/components/permissions-step"
import { SlackStep } from "@/pages/setup/components/slack-step"
import { StackStep } from "@/pages/setup/components/stack-step"
import { TestIncidentStep } from "@/pages/setup/components/test-incident-step"
import { STEP_TITLES, type SetupStepKey } from "@/pages/setup/lib/steps"
import type { OnboardingStep } from "@/types/serializers"

const BODIES: Record<SetupStepKey, (step: OnboardingStep) => ReactNode> = {
  [SETUP_STEPS.ACCOUNT]: () => <AccountStep />,
  [SETUP_STEPS.AI]: (step) => <AiStep step={step} />,
  [SETUP_STEPS.STACK]: () => <StackStep />,
  [SETUP_STEPS.PERMISSIONS]: (step) => <PermissionsStep step={step} />,
  [SETUP_STEPS.HALON]: (step) => <HalonStep step={step} />,
  [SETUP_STEPS.SLACK]: (step) => <SlackStep step={step} />,
  [SETUP_STEPS.TEST_INCIDENT]: (step) => <TestIncidentStep step={step} />,
}

// The open step: where it sits in the list, its name, and what it asks.
export function StepPanel({ step, position, total }: { step: OnboardingStep; position: number; total: number }) {
  return (
    <section aria-labelledby="setup-step-title" className="flex min-w-0 flex-col gap-6">
      <div className="flex flex-col gap-1.5">
        <p className="text-xs font-medium text-fg-muted">
          Step {position} of {total}
        </p>
        <h1 id="setup-step-title" className="text-2xl font-semibold tracking-tight text-fg-headline">
          {STEP_TITLES[step.key]}
        </h1>
      </div>
      {BODIES[step.key](step)}
    </section>
  )
}
