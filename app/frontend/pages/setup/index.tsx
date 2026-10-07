import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { FlashToaster } from "@/components/flash-toaster"
import { Toaster } from "@/components/ui/sonner"
import { TooltipProvider } from "@/components/ui/tooltip"
import { TOAST_OPTIONS } from "@/lib/toast-options"
import { SETUP_STEP_STATES } from "@/lib/generated/constants"
import { SetupHeader } from "@/pages/setup/components/setup-header"
import { SetupRail } from "@/pages/setup/components/setup-rail"
import { StepPanel } from "@/pages/setup/components/step-panel"
import type { SetupStepKey } from "@/pages/setup/lib/steps"
import type { SetupPageProps } from "@/pages/setup/types"

// The checklist after the founder's letter. It opens on the step that is up next, and moves on with it once an answer
// finishes that step, while a finished step stays open for as long as the person looks at it.
export default function Setup() {
  const { steps, workspaceName, email } = usePage<SetupPageProps>().props
  const upNext = steps.find((step) => step.state === SETUP_STEP_STATES.CURRENT) ?? steps[steps.length - 1]
  const [ openKey, setOpenKey ] = useState<SetupStepKey>(upNext.key)
  const [ followed, setFollowed ] = useState<SetupStepKey>(upNext.key)
  if (upNext.key !== followed) {
    setFollowed(upNext.key)
    setOpenKey(upNext.key)
  }
  const open = steps.find((step) => step.key === openKey) ?? upNext

  return (
    <TooltipProvider>
      <Head title={`Set up ${workspaceName}`} />
      <div className="flex min-h-svh flex-col bg-background text-fg-primary">
        <SetupHeader workspaceName={workspaceName} email={email} />
        <main className="mx-auto grid w-full max-w-5xl flex-1 content-start gap-6 px-4 py-6 md:grid-cols-[15rem_minmax(0,1fr)] md:gap-10 md:px-6 md:py-12">
          <SetupRail steps={steps} openKey={open.key} onOpen={setOpenKey} />
          <StepPanel key={open.key} step={open} position={steps.indexOf(open) + 1} total={steps.length} />
        </main>
        <Toaster toastOptions={TOAST_OPTIONS} />
        <FlashToaster />
      </div>
    </TooltipProvider>
  )
}
