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
import { incidentShoutoutPath } from "@/lib/routes"

export function ShoutoutDialog({
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
  const [message, setMessage] = useState("")
  const [saving, setSaving] = useState(false)

  function close() {
    onOpenChange(false)
  }

  function changeMessage(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setMessage(event.target.value)
  }

  function finish() {
    setSaving(false)
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    if (!member || !message.trim()) {
      return
    }

    setSaving(true)
    router.post(
      incidentShoutoutPath(incidentId),
      { member_id: member, message: message.trim() },
      { preserveScroll: true, onSuccess: close, onFinish: finish },
    )
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Give a shoutout</DialogTitle>
            <DialogDescription>
              Posted in the incident channel, where everyone working the incident sees it.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 pt-3 pb-5">
            <div className="flex flex-col gap-2">
              <Label>Who</Label>
              <SearchableSelect
                value={member}
                onValueChange={setMember}
                options={members}
                placeholder="Pick a person"
                searchPlaceholder="Search people..."
                emptyText="No people found"
              />
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="shoutout-message">What they did</Label>
              <Textarea
                id="shoutout-message"
                rows={3}
                value={message}
                onChange={changeMessage}
                placeholder="Found the connection leak in minutes and stayed to see the fix land"
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving || !member || !message.trim()}>
              Post shoutout
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
