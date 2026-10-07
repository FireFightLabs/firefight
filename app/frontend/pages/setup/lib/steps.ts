import { SETUP_STEPS, SETUP_STEP_STATES } from "@/lib/generated/constants"
import type { OnboardingStep } from "@/types/serializers"

export type SetupStepKey = (typeof SETUP_STEPS)[keyof typeof SETUP_STEPS]

// Each step's name in the list and its heading when open.
export const STEP_TITLES: Record<SetupStepKey, string> = {
  [SETUP_STEPS.ACCOUNT]: "Your account",
  [SETUP_STEPS.AI]: "Choose Halon's AI",
  [SETUP_STEPS.STACK]: "Connect your stack",
  [SETUP_STEPS.PERMISSIONS]: "Who can do what",
  [SETUP_STEPS.HALON]: "Meet Halon",
  [SETUP_STEPS.SLACK]: "Connect Slack",
  [SETUP_STEPS.TEST_INCIDENT]: "Run a test incident",
}

// A step that is finished or up next can be opened. One further down waits for the ones above it.
export function canOpen(step: OnboardingStep) {
  return step.state !== SETUP_STEP_STATES.WAITING
}
