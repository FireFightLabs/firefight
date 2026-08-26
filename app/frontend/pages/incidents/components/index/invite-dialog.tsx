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
import {
  SearchableMultiSelect,
  type SearchableMultiSelectOption,
} from "@/components/searchable-multi-select"
import { whenClosed } from "@/lib/handlers"
import { incidentInvitePath } from "@/lib/routes"

export function InviteDialog({
  incidentId,
  members,
  open,
  onOpenChange,
}: {
  incidentId: string
  members: SearchableMultiSelectOption[]
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [picked, setPicked] = useState<string[]>([])
  const [saving, setSaving] = useState(false)

  function close() {
    onOpenChange(false)
  }

  function finish() {
    setSaving(false)
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    if (picked.length === 0) {
      return
    }

    setSaving(true)
    router.post(
      incidentInvitePath(incidentId),
      { member_ids: picked },
      { preserveScroll: true, onSuccess: close, onFinish: finish },
    )
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Bring people in</DialogTitle>
            <DialogDescription>
              They join the incident channel and can see everything from here on. Nobody is asked to
              do anything, so escalate instead when you need a named person to answer.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label>Responders</Label>
            <SearchableMultiSelect
              value={picked}
              onValueChange={setPicked}
              options={members}
              placeholder="Pick people"
              addMoreText="Add someone else..."
              searchPlaceholder="Search people..."
              emptyText="No people found"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={saving || picked.length === 0}>
              Invite
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
