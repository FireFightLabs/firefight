import { useState } from "react"
import { router, usePage } from "@inertiajs/react"

import { WhoCanDoWhat } from "@/components/permissions/who-can-do-what"
import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { onboardingChecklistPermissionsPath } from "@/lib/routes"
import { StepActions } from "@/pages/setup/components/step-actions"
import type { SetupPageProps } from "@/pages/setup/types"
import type { OnboardingStep } from "@/types/serializers"

// The defaults already hold: everyone reads, and changes need a pack. Giving someone a pack here is the same grant as
// under Permissions.
export function PermissionsStep({ step }: { step: OnboardingStep }) {
  const { principals, packs } = usePage<SetupPageProps>().props
  const canManage = useCan("permissions")
  const [ saving, setSaving ] = useState(false)

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
          Everyone in this workspace can ask Halon to read any tool you connected. Anything that changes something, such
          as a restart or a rollback, needs a pack. Each connection brings its own packs, and only an admin gives them.
        </p>
        <p>That is already set up. Give someone a pack now if they will need one, or later under Permissions.</p>
      </div>

      <WhoCanDoWhat people={principals} packs={packs} canManage={canManage} />

      {step.state !== SETUP_STEP_STATES.DONE && <StepActions busy={saving} onContinue={continueOn} />}
    </div>
  )
}
