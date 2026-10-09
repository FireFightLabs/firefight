import { useState } from "react"
import { usePage } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { Blocked } from "@/components/blocked-tooltip"
import { LifecycleFormDialog } from "@/components/incidents/lifecycle-form-dialog"
import type { SetupPageProps } from "@/pages/setup/types"
import type { OnboardingStep } from "@/types/serializers"

// The same test incident the dashboard offers, which runs in Slack. Without Slack the button says why it waits.
export function TestIncidentStep({ step }: { step: OnboardingStep }) {
  const { walkthrough } = usePage<SetupPageProps>().props
  const [ declaring, setDeclaring ] = useState(false)
  const blockedReason = step.state === SETUP_STEP_STATES.CURRENT ? undefined : step.note

  function openDeclare() {
    setDeclaring(true)
  }

  if (step.state === SETUP_STEP_STATES.DONE) {
    return <p className="max-w-prose text-sm leading-relaxed text-fg-body">Your test incident is declared. Work it in its Slack channel and resolve it to see the postmortem.</p>
  }

  return (
    <div className="flex flex-col gap-6">
      <p className="max-w-prose text-sm leading-relaxed text-fg-body">
        See how Firefight works in about three minutes. A test incident works like a real one and is not counted in your
        metrics.
      </p>

      <ol className="flex list-decimal flex-col gap-2.5 pl-5 text-sm leading-relaxed text-fg-body marker:text-fg-muted">
        {walkthrough.map((item, index) => (
          <li key={index}>
            <span className="font-medium text-fg-primary">{item.title}</span> {item.detail}
          </li>
        ))}
      </ol>

      <div className="flex justify-end border-t border-border pt-5">
        <Blocked reason={blockedReason} side="top">
          <Button onClick={openDeclare} disabled={Boolean(blockedReason)}>
            Declare a test incident
          </Button>
        </Blocked>
      </div>

      <LifecycleFormDialog incidentId={null} form="declare" open={declaring} onOpenChange={setDeclaring} test />
    </div>
  )
}
