import { useState } from "react"
import { router, usePage } from "@inertiajs/react"

import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { SETUP_AI_CHOICES, SETUP_STEP_STATES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { onboardingChecklistAiPath } from "@/lib/routes"
import { cn } from "@/lib/utils"
import { AiAccountsCard } from "@/pages/settings/components/workspace/ai-accounts-card"
import { AiCreditsRow } from "@/pages/settings/components/workspace/ai-credits-row"
import { StepActions } from "@/pages/setup/components/step-actions"
import type { SetupPageProps } from "@/pages/setup/types"
import type { OnboardingStep } from "@/types/serializers"

type AiChoice = (typeof SETUP_AI_CHOICES)[keyof typeof SETUP_AI_CHOICES]

const CHOICE_COPY: Record<AiChoice, { title: string; detail: string }> = {
  [SETUP_AI_CHOICES.ACCOUNT]: {
    title: "Use my own AI account",
    detail: "Add an API key from your model provider. Halon's AI costs go to that account.",
  },
  [SETUP_AI_CHOICES.CREDITS]: {
    title: "Use Firefight credits",
    detail: "Prepaid credits on this workspace. Firefight runs the models and takes each call from the balance.",
  },
  [SETUP_AI_CHOICES.HOUSE]: {
    title: "Use the AI keys this Firefight runs on",
    detail: "Whoever runs this Firefight already set up model keys, and Halon can use them.",
  },
}

function isChoice(value: string): value is AiChoice {
  return Object.values<string>(SETUP_AI_CHOICES).includes(value)
}

// Halon needs a model to write with. The person's own key is always offered, with its live check, and Firefight credits
// or the deployment's own keys where this Firefight has them.
export function AiStep({ step }: { step: OnboardingStep }) {
  const { aiChoice, aiChoices, aiAccounts, aiProviders, aiSignIn, aiFallback, aiCredits } = usePage<SetupPageProps>().props
  const canManageAccounts = useCan("ai_accounts")
  const offered = Object.keys(aiChoices).filter(isChoice)
  const [ choice, setChoice ] = useState<AiChoice>(aiChoice && isChoice(aiChoice) && offered.includes(aiChoice) ? aiChoice : SETUP_AI_CHOICES.ACCOUNT)
  const [ saving, setSaving ] = useState(false)

  function pick(value: string) {
    if (isChoice(value)) {
      setChoice(value)
    }
  }

  function stopSaving() {
    setSaving(false)
  }

  function save() {
    setSaving(true)
    router.post(onboardingChecklistAiPath(), { choice }, { onFinish: stopSaving })
  }

  return (
    <div className="flex flex-col gap-6">
      <p className="max-w-prose text-sm leading-relaxed text-fg-body">
        Halon investigates, answers and writes postmortems with a model from an AI provider. Choose how it gets one. You
        can change this later under Settings, Workspace.
      </p>

      {offered.length > 1 && (
        <RadioGroup value={choice} onValueChange={pick} className="gap-2" aria-label="How Halon gets its AI">
          {offered.map((value) => (
            <Label
              key={value}
              htmlFor={`ai-choice-${value}`}
              className={cn(
                "flex cursor-pointer items-start gap-3 rounded-lg border p-4 font-normal transition-colors duration-150",
                choice === value ? "border-brand-border bg-brand-tint" : "border-border hover:bg-surface-hover",
              )}
            >
              <RadioGroupItem value={value} id={`ai-choice-${value}`} className="mt-0.5" />
              <span className="flex flex-col gap-0.5">
                <span className="text-sm font-medium text-fg-primary">{CHOICE_COPY[value].title}</span>
                <span className="text-xs leading-relaxed text-fg-secondary">{CHOICE_COPY[value].detail}</span>
              </span>
            </Label>
          ))}
        </RadioGroup>
      )}

      {choice === SETUP_AI_CHOICES.ACCOUNT && (
        <AiAccountsCard
          accounts={aiAccounts}
          providers={aiProviders}
          signIn={aiSignIn}
          fallback={aiFallback}
          credits={null}
          canManage={canManageAccounts}
        />
      )}

      {choice === SETUP_AI_CHOICES.CREDITS && aiCredits && (
        <div className="border-border overflow-hidden rounded-lg border [&>div]:border-t-0">
          <AiCreditsRow credits={aiCredits} canManage={canManageAccounts} />
        </div>
      )}

      <StepActions
        label={step.state === SETUP_STEP_STATES.DONE ? "Save" : "Continue"}
        blockedReason={aiChoices[choice]}
        busy={saving}
        onContinue={save}
      />
    </div>
  )
}
