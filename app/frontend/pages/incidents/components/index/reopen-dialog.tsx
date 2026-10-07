import { useState } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { REOPEN_REASON_LIMIT } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { incidentReopenPath } from "@/lib/routes"
import { afterMutation } from "@/pages/incidents/lib/after-mutation"

// Asks what Slack's Reopen form asks, an optional reason, which goes into the timeline and the channel's message.
export function ReopenDialog({
  incidentId,
  open,
  onOpenChange,
}: {
  incidentId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)

  function close() {
    onOpenChange(false)
  }

  function changeReason(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setReason(event.target.value)
  }

  function finish() {
    setSaving(false)
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    setSaving(true)
    router.patch(
      incidentReopenPath(incidentId),
      { reason: reason.trim() },
      { ...afterMutation("incident", "timelineEvents"), onSuccess: close, onFinish: finish },
    )
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Reopen incident</DialogTitle>
            <DialogDescription>
              Firefight posts the reopen in the incident channel, with your reason when you give one.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label htmlFor="reopen-reason">
              Reason for reopening <span className="font-normal text-muted-foreground">(optional)</span>
            </Label>
            <Textarea
              id="reopen-reason"
              rows={3}
              maxLength={REOPEN_REASON_LIMIT}
              value={reason}
              onChange={changeReason}
              placeholder="Why is this incident being reopened?"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving}>
              Reopen incident
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
