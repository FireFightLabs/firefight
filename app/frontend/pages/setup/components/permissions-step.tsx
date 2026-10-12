import { useState } from "react"
import { Link, router, usePage } from "@inertiajs/react"

import { MemberAccessTable } from "@/components/permissions/member-access-table"
import { SETUP_STEPS, SETUP_STEP_STATES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { onboardingChecklistPath, onboardingChecklistPermissionsPath } from "@/lib/routes"
import { StepActions } from "@/pages/setup/components/step-actions"
import { STEP_TITLES } from "@/pages/setup/lib/steps"
import type { SetupPageProps } from "@/pages/setup/types"
import type { MemberAccess, OnboardingStep } from "@/types/serializers"

// Each choice saves the moment it is made, to the same grants as the Permissions screen, so Continue only moves setup on
// and a row left alone changes nothing.
export function PermissionsStep({ step }: { step: OnboardingStep }) {
  const { memberAccess } = usePage<SetupPageProps>().props
  const canManage = useCan("permissions")
  const [ saving, setSaving ] = useState(false)
  const laterNote = invitedLaterNote(memberAccess)

  function stopSaving() {
    setSaving(false)
  }

  function continueOn() {
    setSaving(true)
    router.post(onboardingChecklistPermissionsPath(), {}, { onFinish: stopSaving })
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex max-w-prose flex-col gap-3 text-sm leading-relaxed text-fg-body">
        <p>
          Choose what people in your workspace can ask Halon to look at or change in each tool. Admins can always do
          everything.
        </p>
        {laterNote && <p>{laterNote}</p>}
      </div>

      <MemberAccessTable
        access={memberAccess}
        canManage={canManage}
        empty={
          <p>
            Nothing is connected yet, so there is nothing to choose.{" "}
            <Link href={onboardingChecklistPath({ step: SETUP_STEPS.STACK })} className="text-fg-primary underline underline-offset-4">
              Go back to {STEP_TITLES[SETUP_STEPS.STACK]}
            </Link>{" "}
            to connect a tool.
          </p>
        }
      />

      {step.state !== SETUP_STEP_STATES.DONE && <StepActions busy={saving} onContinue={continueOn} />}
    </div>
  )
}

// With nobody but admins here yet, the choices are for whoever is invited next.
function invitedLaterNote(access: MemberAccess): string | null {
  if (access.members.length > 0) {
    return null
  }
  if (access.peopleCount <= 1) {
    return "You are the only one here so far, so these choices apply to people you invite later."
  }
  return "Everyone here so far is an admin, so these choices apply to people you invite later."
}
