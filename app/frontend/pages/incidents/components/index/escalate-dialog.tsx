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
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { whenClosed } from "@/lib/handlers"
import { incidentEscalatePath } from "@/lib/routes"

export function EscalateDialog({
  incidentId,
  members,
  open,
  onOpenChange,
}: {
  incidentId: string
  members: SearchableSelectOption[]
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [member, setMember] = useState<string | null>(null)
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
    if (!member || !reason.trim()) {
      return
    }

    setSaving(true)
    router.post(
      incidentEscalatePath(incidentId),
      { member_id: member, reason: reason.trim() },
      { preserveScroll: true, onSuccess: close, onFinish: finish },
    )
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Ask someone to pick this up</DialogTitle>
            <DialogDescription>
              They get a message of their own with an acknowledge button, and a reminder if they do
              not answer. The ask is posted in the incident channel too.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 pt-3 pb-5">
            <div className="flex flex-col gap-2">
              <Label>Who</Label>
              <SearchableSelect
                value={member}
                onValueChange={setMember}
                options={members}
                placeholder="Pick a responder"
                searchPlaceholder="Search people..."
                emptyText="No people found"
              />
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="escalation-reason">Why you need them</Label>
              <Textarea
                id="escalation-reason"
                rows={3}
                value={reason}
                onChange={changeReason}
                placeholder="Replica 2 is still refusing connections and I cannot reach the pooler"
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving || !member || !reason.trim()}>
              Escalate
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
