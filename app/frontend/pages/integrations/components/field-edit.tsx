import { type ChangeEvent, type FormEvent, useState } from "react"
import { router } from "@inertiajs/react"

import type { Integration } from "@/types/serializers"
import { editFieldIntegrationPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { whenClosed } from "@/lib/handlers"

type Edit = Integration["environments"][number]["edits"][number]

// A label inside a sentence, its first letter lower case and the rest as written, so "Service token ID" keeps its ID.
function inSentence(label: string) {
  return label.charAt(0).toLowerCase() + label.slice(1)
}

// A field asked on the connect form that can be changed after connecting, such as a token's id, shown with what it holds
// and changed in a dialog. Saving checks the connection again with it and says so in a toast.
export function FieldEdit({
  integrationId,
  rowId,
  edit,
  canManage,
}: {
  integrationId: string
  rowId: string
  edit: Edit
  canManage: boolean
}) {
  const [open, setOpen] = useState(false)

  function openDialog() {
    setOpen(true)
  }

  function closeDialog() {
    setOpen(false)
  }

  return (
    <div className="flex items-center justify-between gap-3 px-3 pb-2.5">
      <div className="min-w-0">
        <p className="text-sm font-medium">{edit.label}</p>
        <p className="text-muted-foreground truncate text-xs" title={edit.value ?? undefined}>
          {edit.value ?? "Not set"}
        </p>
      </div>
      <Button size="sm" variant="outline" className="shrink-0" onClick={openDialog} disabled={!canManage}>
        {edit.value ? "Change" : "Add"}
      </Button>
      <Dialog open={open} onOpenChange={whenClosed(closeDialog)}>
        <DialogContent className="sm:max-w-md">
          {open && <FieldEditForm integrationId={integrationId} rowId={rowId} edit={edit} onDone={closeDialog} />}
        </DialogContent>
      </Dialog>
    </div>
  )
}

// Mounted only while open, so each opening starts from what the field holds now.
function FieldEditForm({
  integrationId,
  rowId,
  edit,
  onDone,
}: {
  integrationId: string
  rowId: string
  edit: Edit
  onDone: () => void
}) {
  const [draft, setDraft] = useState(edit.value ?? "")
  const [saving, setSaving] = useState(false)
  const fieldId = `edit-${rowId}-${edit.key}`

  function change(event: ChangeEvent<HTMLInputElement>) {
    setDraft(event.target.value)
  }

  function finish() {
    setSaving(false)
    onDone()
  }

  function save(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    router.patch(
      editFieldIntegrationPath(integrationId),
      { environment_row_id: rowId, key: edit.key, value: draft.trim() },
      { preserveScroll: true, onFinish: finish },
    )
  }

  return (
    <form onSubmit={save}>
      <DialogHeader>
        <DialogTitle>{edit.value ? `Change ${inSentence(edit.label)}` : `Add ${inSentence(edit.label)}`}</DialogTitle>
        <DialogDescription>{edit.hint}</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-2 py-4">
        <Label htmlFor={fieldId}>{edit.label}</Label>
        <Input
          id={fieldId}
          value={draft}
          onChange={change}
          placeholder={edit.placeholder}
          autoComplete="off"
          spellCheck={false}
          autoFocus
        />
      </div>
      <DialogFooter>
        <Button type="button" variant="outline" onClick={onDone} disabled={saving}>
          Cancel
        </Button>
        <Button type="submit" disabled={saving || draft.trim() === (edit.value ?? "")}>
          Save
        </Button>
      </DialogFooter>
    </form>
  )
}
