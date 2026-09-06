import { useRef } from "react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import type { OnboardingStep } from "@/pages/dashboard/types"

export function OnboardingDialog({
  open,
  steps,
  incidentsChannelUrl,
  onDeclare,
  onDismiss,
}: {
  open: boolean
  steps: OnboardingStep[]
  incidentsChannelUrl: string | null
  onDeclare: () => void
  onDismiss: () => void
}) {
  const declareRef = useRef<HTMLButtonElement>(null)

  // The first thing to click is the first thing focused, not the close cross.
  function focusDeclare(event: Event) {
    event.preventDefault()
    declareRef.current?.focus()
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-md" onOpenAutoFocus={focusDeclare}>
        <DialogHeader>
          <DialogTitle>Three steps to see how Firefight works</DialogTitle>
          <DialogDescription>Takes about three minutes. The test incident is not counted in your metrics.</DialogDescription>
        </DialogHeader>

        <ol className="flex flex-col gap-2.5 pl-5 text-sm leading-relaxed text-foreground/85 list-decimal marker:text-muted-foreground">
          {steps.map((step) => (
            <li key={step.title}>
              <span className="font-medium text-foreground">{step.title}</span> {step.detail}
            </li>
          ))}
        </ol>

        <div className="flex flex-col gap-3 pt-1">
          <Button ref={declareRef} type="button" className="w-full" onClick={onDeclare}>
            Declare a test incident
          </Button>
          <div className="flex items-center justify-between">
            {incidentsChannelUrl ? (
              <a
                href={incidentsChannelUrl}
                className="text-xs text-muted-foreground underline decoration-border underline-offset-[3px] transition-colors hover:text-foreground hover:decoration-foreground"
              >
                Open #incidents instead
              </a>
            ) : (
              <span />
            )}
            <Button type="button" variant="ghost" size="sm" className="text-muted-foreground" onClick={onDismiss}>
              Not now
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
