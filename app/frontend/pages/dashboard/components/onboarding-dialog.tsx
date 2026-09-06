import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
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
  return (
    <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Three steps to see how Firefight works</DialogTitle>
          <DialogDescription>Takes about three minutes. The test incident is not counted in your metrics.</DialogDescription>
        </DialogHeader>

        <ol className="flex flex-col gap-2.5 py-1 pl-5 text-sm leading-relaxed text-foreground/85 list-decimal marker:text-muted-foreground">
          {steps.map((step) => (
            <li key={step.title}>
              <span className="font-medium text-foreground">{step.title}</span> {step.detail}
            </li>
          ))}
        </ol>

        <DialogFooter className="sm:justify-between sm:items-center">
          {incidentsChannelUrl ? (
            <a
              href={incidentsChannelUrl}
              className="whitespace-nowrap text-xs text-muted-foreground underline decoration-border underline-offset-[3px] transition-colors hover:text-foreground hover:decoration-foreground"
            >
              Open #incidents instead
            </a>
          ) : (
            <span />
          )}
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onDismiss}>
              Not now
            </Button>
            <Button type="button" onClick={onDeclare}>
              Declare a test incident
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
