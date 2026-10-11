import { useState } from "react"
import { router, usePage } from "@inertiajs/react"
import { IconCheck, IconCircleCheck } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { StepActions } from "@/pages/setup/components/step-actions"
import type { SetupPageProps } from "@/pages/setup/types"
import type { SetupPlan } from "@/types/serializers"

function startLabel(plan: SetupPlan) {
  return plan.trialDays ? `Start your ${plan.trialDays}-day trial` : "Continue to payment"
}

// Shown once a trial or the plan is running, with the way to the billing page where it can be canceled.
function PlanRunning({ plan, billingPath }: { plan: SetupPlan; billingPath?: string }) {
  return (
    <div className="flex flex-col gap-6">
      <div className="border-border flex items-start gap-3 rounded-lg border p-4">
        <IconCircleCheck className="mt-0.5 size-5 shrink-0 text-brand" />
        <p className="text-sm leading-relaxed text-fg-body">{plan.summary}</p>
      </div>
      {billingPath && (
        <div className="flex justify-end border-t border-border pt-5">
          <Button asChild variant="outline">
            <a href={billingPath}>Open billing</a>
          </Button>
        </div>
      )}
    </div>
  )
}

// The one plan, its price and what comes with it. Starting it opens the payment page, which takes the card, and setup
// carries on once the trial or the plan is running.
export function PlanStep() {
  const { plan, cloudBillingPath } = usePage<SetupPageProps>().props
  const [ opening, setOpening ] = useState(false)

  if (!plan) {
    return null
  }

  if (plan.active) {
    return <PlanRunning plan={plan} billingPath={cloudBillingPath} />
  }

  const startPath = plan.startPath

  function stopOpening() {
    setOpening(false)
  }

  function startPlan() {
    setOpening(true)
    router.post(startPath, {}, { onFinish: stopOpening })
  }

  return (
    <div className="flex flex-col gap-6">
      <p className="max-w-prose text-sm leading-relaxed text-fg-body">
        {plan.trialDays
          ? `Firefight is one plan with everything in it. Try it free for ${plan.trialDays} days, and setup carries on once your trial has started.`
          : "Firefight is one plan with everything in it. Setup carries on once your plan has started."}
      </p>

      <div className="rounded-xl border border-border bg-surface-card p-5 sm:p-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <p className="text-lg font-semibold text-fg-headline">Firefight</p>
          <div className="flex flex-col gap-1.5 sm:items-end">
            <p className="text-fg-primary">
              <span className="text-2xl font-semibold tabular-nums">{plan.price}</span>
              <span className="text-sm text-fg-secondary"> a month</span>
            </p>
            <Badge variant="secondary">{plan.priceNote}</Badge>
          </div>
        </div>

        <ul className="mt-5 flex flex-col gap-2.5 text-sm text-fg-body">
          {plan.included.map((line) => (
            <li key={line} className="flex items-start gap-2.5">
              <IconCheck className="mt-0.5 size-4 shrink-0 text-fg-secondary" />
              <span>{line}</span>
            </li>
          ))}
        </ul>
      </div>

      <div className="flex max-w-prose flex-col gap-2 text-xs leading-relaxed text-fg-muted">
        <p>{plan.terms}</p>
        <p>
          By continuing you agree to the{" "}
          <a href="https://firefight.app/terms" target="_blank" rel="noreferrer" className="underline underline-offset-2">
            terms of service
          </a>
          .
        </p>
      </div>

      <StepActions
        label={opening ? "Opening payment…" : startLabel(plan)}
        blockedReason={plan.startBlockedReason}
        busy={opening}
        onContinue={startPlan}
      />
    </div>
  )
}
