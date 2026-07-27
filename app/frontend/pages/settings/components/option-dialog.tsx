import { useState, type FormEvent, type ReactNode } from "react"
import { router } from "@inertiajs/react"

import { ColorPicker } from "@/components/color-picker"
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
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

interface OptionRecord {
  id: string
  name: string
  description?: string | null
  color?: string | null
}

export type OptionDialogState<T> = { mode: "create" } | { mode: "edit"; option: T } | null

// Owns both halves of the create/edit pair so a tab renders one dialog rather
// than two near-identical ones, and derives its wording from the noun so the
// four screens cannot drift apart.
export function OptionDialog<T extends OptionRecord>({
  state,
  onClose,
  noun,
  createTitle,
  createDescription,
  createPath,
  editPath,
  defaultColor,
  namePlaceholder,
  descriptionPlaceholder,
  extraParams,
  footnote,
}: {
  state: OptionDialogState<T>
  onClose: () => void
  noun: string
  createTitle?: string
  createDescription?: string
  createPath: string
  editPath: (id: string) => string
  // Omitted for option lists that have no colour.
  defaultColor?: string
  namePlaceholder?: string
  descriptionPlaceholder?: string
  extraParams?: Record<string, string>
  footnote?: ReactNode
}) {
  const editing = state?.mode === "edit" ? state.option : null
  const lower = noun.toLowerCase()

  const [draft, setDraft] = useState({ name: "", description: "", color: defaultColor })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [processing, setProcessing] = useState(false)

  // Re-seed when the dialog opens, and when it is reused for a different row.
  const identity = `${state?.mode ?? "closed"}:${editing?.id ?? ""}`
  const [lastIdentity, setLastIdentity] = useState<string | null>(null)
  if (state && identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft({
      name: editing?.name ?? "",
      description: editing?.description ?? "",
      color: editing?.color ?? defaultColor,
    })
    setErrors({})
  }

  const fieldId = (field: string) => `option-${field}-${editing?.id ?? "new"}`

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setProcessing(true)

    const send = editing ? router.patch : router.post
    send(editing ? editPath(editing.id) : createPath, { ...draft, ...extraParams }, {
      preserveScroll: true,
      onSuccess: onClose,
      onError: setErrors,
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <Dialog open={Boolean(state)} onOpenChange={(open) => { if (!open) onClose() }}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>
              {editing ? `Edit ${noun}` : createTitle ?? `Add ${noun}`}
            </DialogTitle>
            <DialogDescription>
              {editing
                ? `Update the name, description${defaultColor ? ", or color" : ""} for this ${lower}.`
                : createDescription ?? `Create a new ${lower} for your workspace.`}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("name")}>Name</Label>
              <Input
                id={fieldId("name")}
                placeholder={namePlaceholder}
                value={draft.name}
                onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              />
              {errors.name && <p className="text-xs text-destructive">{errors.name}</p>}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("description")}>Description</Label>
              <Textarea
                id={fieldId("description")}
                rows={2}
                placeholder={descriptionPlaceholder}
                value={draft.description}
                onChange={(e) => setDraft({ ...draft, description: e.target.value })}
              />
            </div>

            {draft.color !== undefined && (
              <div className="flex flex-col gap-2">
                <Label htmlFor={fieldId("color")}>Color</Label>
                <ColorPicker
                  id={fieldId("color")}
                  value={draft.color}
                  onChange={(color) => setDraft({ ...draft, color })}
                />
              </div>
            )}

            {!editing && footnote}
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {editing ? "Save Changes" : `Create ${noun}`}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
