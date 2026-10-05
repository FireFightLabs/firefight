import { useForm } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { renameIncidentItemPath } from "@/lib/routes"
import { afterMutation } from "@/pages/incidents/lib/after-mutation"
import type { IncidentAction } from "@/pages/incidents/types"

// The same form as adding an item, holding the title it has now. Its issue, when it has one, takes the new title.
export function RenameItemDialog({
  action,
  incidentId,
  open,
  onOpenChange,
}: {
  action: IncidentAction
  incidentId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { data, setData, patch, processing } = useForm({ description: action.description })

  function close() {
    onOpenChange(false)
  }

  function changeDescription(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setData("description", event.target.value)
  }

  function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    patch(renameIncidentItemPath(incidentId, action.id), { ...afterMutation("actions", "timelineEvents"), onSuccess: close })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Rename the item</DialogTitle>
            <DialogDescription>
              {action.externalKey
                ? `${action.externalKey} takes the new title too.`
                : "Say what needs doing, the way it reads in the incident."}
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label htmlFor={`rename-${action.id}`}>Title</Label>
            <Textarea
              id={`rename-${action.id}`}
              rows={3}
              className="resize-none"
              value={data.description}
              onChange={changeDescription}
              required
            />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>Cancel</Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || !data.description.trim() || data.description.trim() === action.description}>
              {processing ? "Saving…" : "Rename"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
