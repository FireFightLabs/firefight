import { router } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { whenClosed } from "@/lib/handlers"
import { investigationFixPath } from "@/lib/routes"
import type { InvestigationRemediationPlan } from "@/types/serializers"

function pluralSteps(count: number): string {
  return count === 1 ? "1 step" : `${count} steps`
}

function whatRuns(runs: number, byHand: number): string {
  const said = `Runs ${pluralSteps(runs)} through your connections, as you, in order.`
  if (byHand === 0) {
    return said
  }
  return `${said} ${pluralSteps(byHand)} for a person ${byHand === 1 ? "is" : "are"} marked done here as you do them.`
}

// Applying runs the fix's tool steps for real, as whoever clicks, so it asks first and says what will run.
export function ApplyFix({ investigationId, fix }: { investigationId: string; fix: InvestigationRemediationPlan }) {
  const [ open, setOpen ] = useState(false)
  const [ applying, setApplying ] = useState(false)
  const runs = fix.steps.filter((step) => step.runsItself)
  const byHand = fix.steps.length - runs.length
  const what = fix.isUndo ? "undo" : "fix"

  function openDialog() {
    setOpen(true)
  }

  function closeDialog() {
    setOpen(false)
  }

  function finished() {
    setApplying(false)
    setOpen(false)
  }

  function apply() {
    setApplying(true)
    router.post(investigationFixPath(investigationId), { plan_id: fix.id }, { preserveScroll: true, onFinish: finished })
  }

  const button = (
    <Button type="button" size="sm" className="w-fit" disabled={fix.applyBlockedReason != null} onClick={openDialog}>
      Apply {what}
    </Button>
  )

  return (
    <>
      {fix.applyBlockedReason ? (
        <Tooltip>
          <TooltipTrigger asChild>
            <span className="w-fit">{button}</span>
          </TooltipTrigger>
          <TooltipContent>{fix.applyBlockedReason}</TooltipContent>
        </Tooltip>
      ) : (
        button
      )}
      <Dialog open={open} onOpenChange={whenClosed(closeDialog)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Apply this {what}?</DialogTitle>
            <DialogDescription>{whatRuns(runs.length, byHand)}</DialogDescription>
          </DialogHeader>
          <ol className="flex flex-col gap-1.5 text-sm">
            {runs.map((step) => (
              <li key={step.id} className="flex gap-2">
                <span className="tabular-nums text-fg-muted">{step.position}.</span>
                <span className="min-w-0 text-fg-body">
                  {step.description}
                  {step.action && <code className="ml-1.5 font-mono text-xs text-fg-secondary">{step.action}</code>}
                </span>
              </li>
            ))}
          </ol>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={closeDialog}>Cancel</Button>
            <Button type="button" disabled={applying} onClick={apply}>
              {applying && <IconLoader2 className="motion-safe:animate-spin" />}
              {applying ? "Applying" : `Apply ${what}`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
