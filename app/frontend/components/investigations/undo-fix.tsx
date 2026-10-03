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
import { whenClosed } from "@/lib/handlers"
import { investigationFixUndoPath } from "@/lib/routes"
import type { InvestigationRemediationPlan } from "@/types/serializers"

// Halon writes the steps that put back what an applied fix changed, and they show below to apply like the fix, so
// asking changes nothing yet. A failed writing says why and can be asked again.
export function UndoFix({ investigationId, fix }: { investigationId: string; fix: InvestigationRemediationPlan }) {
  const [ open, setOpen ] = useState(false)
  const [ asking, setAsking ] = useState(false)

  function openDialog() {
    setOpen(true)
  }

  function closeDialog() {
    setOpen(false)
  }

  function finished() {
    setAsking(false)
    setOpen(false)
  }

  function ask() {
    setAsking(true)
    router.post(investigationFixUndoPath(investigationId), {}, { preserveScroll: true, onFinish: finished })
  }

  if (fix.writingUndo) {
    return (
      <p className="flex items-center gap-1.5 text-xs text-fg-secondary">
        <IconLoader2 className="size-3.5 animate-spin" />
        Halon is writing the undo.
      </p>
    )
  }
  if (fix.undoBlockedReason) {
    return null
  }

  return (
    <div className="flex flex-col gap-1.5">
      {fix.undoError && <p className="text-xs text-warning">{fix.undoError}</p>}
      <Button type="button" size="sm" variant="outline" className="w-fit" onClick={openDialog}>
        Undo fix
      </Button>
      <Dialog open={open} onOpenChange={whenClosed(closeDialog)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Write the undo?</DialogTitle>
            <DialogDescription>
              Halon writes the steps that put back what this fix changed, from what each step did. Nothing changes until
              someone applies them.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={closeDialog}>Cancel</Button>
            <Button type="button" disabled={asking} onClick={ask}>{asking ? "Asking" : "Write the undo"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
