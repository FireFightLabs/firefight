import { useState } from "react"
import { router, usePage } from "@inertiajs/react"

import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { SETUP_AI_CHOICES, SETUP_STEP_STATES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { onboardingChecklistAiPath } from "@/lib/routes"
import { cn } from "@/lib/utils"
import { AiAccountsCard } from "@/components/ai/ai-accounts-card"
import { AiCreditsRow } from "@/components/ai/ai-credits-row"
import { CreditPacks, creditPriceNote } from "@/components/ai/credit-packs"
import { StepActions } from "@/pages/setup/components/step-actions"
import type { SetupPageProps } from "@/pages/setup/types"
import type { OnboardingStep } from "@/types/serializers"

type AiChoice = (typeof SETUP_AI_CHOICES)[keyof typeof SETUP_AI_CHOICES]

function isChoice(value: string): value is AiChoice {
  return Object.values<string>(SETUP_AI_CHOICES).includes(value)
}

// Halon needs a model to write with. The person's own key is always offered, with its live check, and Firefight credits
// or the deployment's own keys where this Firefight has them. Each choice arrives in the words the server gives it.
export function AiStep({ step }: { step: OnboardingStep }) {
  const { aiChoice, aiChoices, aiAccounts, aiProviders, aiSignIn, aiFallback, aiCredits, aiCreditPurchase } = usePage<SetupPageProps>().props
  const canManageAccounts = useCan("ai_accounts")
  // Packs bought here bring the person back to this step, so the row's link away to billing is left off.
  const purchase = canManageAccounts ? aiCreditPurchase : null
  const offeredValues = aiChoices.map((option) => option.value)
  const [ choice, setChoice ] = useState<AiChoice>(aiChoice && isChoice(aiChoice) && offeredValues.includes(aiChoice) ? aiChoice : SETUP_AI_CHOICES.ACCOUNT)
  const [ saving, setSaving ] = useState(false)

  const blockedReason = aiChoices.find((option) => option.value === choice)?.blockedReason ?? null

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

      {aiChoices.length > 1 && (
        <RadioGroup value={choice} onValueChange={pick} className="gap-2" aria-label="How Halon gets its AI">
          {aiChoices.map((option) => (
            <Label
              key={option.value}
              htmlFor={`ai-choice-${option.value}`}
              className={cn(
                "flex cursor-pointer items-start gap-3 rounded-lg border p-4 font-normal transition-colors duration-150",
                choice === option.value ? "border-brand-border bg-brand-tint" : "border-border hover:bg-surface-hover",
              )}
            >
              <RadioGroupItem value={option.value} id={`ai-choice-${option.value}`} className="mt-0.5" />
              <span className="flex flex-col gap-0.5">
                <span className="text-sm font-medium text-fg-primary">{option.title}</span>
                <span className="text-xs leading-relaxed text-fg-secondary">{option.detail}</span>
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
        <div className="border-border overflow-hidden rounded-lg border [&>div:first-child]:border-t-0">
          <AiCreditsRow credits={aiCredits} canManage={canManageAccounts && !purchase} />
          {purchase && (
            <div className="flex flex-col gap-3 border-t px-4 py-3">
              <div className="flex flex-col gap-1 text-xs leading-relaxed text-muted-foreground">
                {purchase.note && <p className="text-sm text-fg-primary">{purchase.note}</p>}
                <p>{creditPriceNote(purchase.markupPercent)}</p>
                {purchase.estimate && <p>{purchase.estimate}</p>}
              </div>
              <div className="flex flex-col gap-2">
                <span className="text-xs font-medium text-fg-secondary">Buy more</span>
                <CreditPacks packs={purchase.packs} blockedReason={purchase.blockedReason} checkoutPath={purchase.checkoutPath} />
              </div>
            </div>
          )}
        </div>
      )}

      <StepActions
        label={step.state === SETUP_STEP_STATES.DONE ? "Save" : "Continue"}
        blockedReason={blockedReason}
        busy={saving}
        onContinue={save}
      />
    </div>
  )
}
