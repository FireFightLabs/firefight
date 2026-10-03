import { router } from "@inertiajs/react"
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
import { whenClosed } from "@/lib/handlers"
import { investigationFixCancelPath } from "@/lib/routes"
import type { InvestigationRemediationPlan } from "@/types/serializers"

// The same words Slack's confirm uses.
function cancelText(fix: InvestigationRemediationPlan): string {
  const said = "Steps that have not run never will, and approvals they wait on are withdrawn. A step already running finishes"
  return fix.isUndo ? `${said}.` : `${said}, and whatever went through can be undone.`
}

// Stops a fix being applied. What has not run never will, and a step already running finishes, so it asks first.
export function CancelFix({ investigationId, fix }: { investigationId: string; fix: InvestigationRemediationPlan }) {
  const [ open, setOpen ] = useState(false)
  const [ cancelling, setCancelling ] = useState(false)
  const what = fix.isUndo ? "undo" : "fix"

  function openDialog() {
    setOpen(true)
  }

  function closeDialog() {
    setOpen(false)
  }

  function finished() {
    setCancelling(false)
    setOpen(false)
  }

  function cancel() {
    setCancelling(true)
    router.post(investigationFixCancelPath(investigationId), { plan_id: fix.id }, { preserveScroll: true, onFinish: finished })
  }

  if (fix.cancelBlockedReason) {
    return null
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" className="w-fit" onClick={openDialog}>
        Cancel {what}
      </Button>
      <Dialog open={open} onOpenChange={whenClosed(closeDialog)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Cancel this {what}?</DialogTitle>
            <DialogDescription>{cancelText(fix)}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={closeDialog}>Keep going</Button>
            <Button type="button" variant="destructive" disabled={cancelling} onClick={cancel}>
              {cancelling ? "Cancelling" : `Cancel ${what}`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
