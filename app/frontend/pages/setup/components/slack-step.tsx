import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconBrandSlack } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { onboardingChecklistSkipSlackPath, onboardingConnectSlackPath } from "@/lib/routes"
import type { OnboardingStep } from "@/types/serializers"

function connectSlack() {
  router.post(onboardingConnectSlackPath())
}

// Incidents run in Slack, each in its own channel. It can wait, and then every page says so until it is connected.
export function SlackStep({ step }: { step: OnboardingStep }) {
  const [ skipping, setSkipping ] = useState(false)

  function stopSkipping() {
    setSkipping(false)
  }

  function notNow() {
    setSkipping(true)
    router.post(onboardingChecklistSkipSlackPath(), {}, { onFinish: stopSkipping })
  }

  if (step.state === SETUP_STEP_STATES.DONE) {
    return <p className="max-w-prose text-sm leading-relaxed text-fg-body">Slack is connected. Each incident gets its own channel there.</p>
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex max-w-prose flex-col gap-3 text-sm leading-relaxed text-fg-body">
        <p>
          Firefight runs each incident in its own Slack channel, where your team declares it, works it and resolves it.
          Halon answers there too.
        </p>
        <p>
          {step.state === SETUP_STEP_STATES.SKIPPED
            ? "You chose to connect it later. Until then, every page shows a Connect Slack banner and incidents wait for it."
            : "You can connect it later. Until then, every page shows a Connect Slack banner and incidents wait for it."}
        </p>
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-end">
        {step.state !== SETUP_STEP_STATES.SKIPPED && (
          <Button variant="ghost" onClick={notNow} disabled={skipping}>
            Not now
          </Button>
        )}
        <Button onClick={connectSlack}>
          <IconBrandSlack className="size-4" />
          Connect Slack
        </Button>
      </div>
    </div>
  )
}
