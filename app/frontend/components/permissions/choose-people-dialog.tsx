import { useState } from "react"
import { IconUser } from "@tabler/icons-react"

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
import { SearchableMultiSelect, type SearchableMultiSelectOption } from "@/components/searchable-multi-select"
import { whenClosed } from "@/lib/handlers"

// Picks the members who can read or change a connection. Opened fresh each time, so it starts from who holds it now.
export function ChoosePeopleDialog({
  title,
  description,
  members,
  initial,
  saving,
  onSave,
  onDismiss,
}: {
  title: string
  description: string
  members: { id: string; name: string }[]
  initial: string[]
  saving: boolean
  onSave: (peopleIds: string[]) => void
  onDismiss: () => void
}) {
  const [picked, setPicked] = useState<string[]>(initial)

  const options: SearchableMultiSelectOption[] = members.map((member) => ({
    value: member.id,
    label: member.name,
    icon: <IconUser className="text-muted-foreground size-4" />,
  }))

  function submit(event: React.FormEvent) {
    event.preventDefault()
    if (picked.length === 0) {
      return
    }
    onSave(picked)
  }

  return (
    <Dialog open onOpenChange={whenClosed(onDismiss)}>
      <DialogContent onOpenAutoFocus={(event) => event.preventDefault()}>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2 pt-3 pb-5">
            <Label>People</Label>
            <SearchableMultiSelect
              value={picked}
              onValueChange={setPicked}
              options={options}
              placeholder="Pick people"
              addMoreText="Add someone else..."
              searchPlaceholder="Search people..."
              emptyText="No people found"
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onDismiss}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || picked.length === 0}>
              Save
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
