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

export interface OptionDraft {
  id?: string
  name: string
  description: string
  color: string
}

export function OptionDialog({
  open,
  onOpenChange,
  title,
  description,
  submitLabel,
  namePlaceholder,
  descriptionPlaceholder,
  initial,
  action,
  method,
  extraParams,
  footnote,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: string
  submitLabel: string
  namePlaceholder?: string
  descriptionPlaceholder?: string
  initial: OptionDraft
  action: string
  method: "post" | "patch"
  extraParams?: Record<string, string>
  footnote?: ReactNode
}) {
  const [draft, setDraft] = useState(initial)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [processing, setProcessing] = useState(false)

  const identity = `${open}:${initial.id ?? "new"}`
  const [lastIdentity, setLastIdentity] = useState(identity)
  if (identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft(initial)
    setErrors({})
  }

  const fieldId = (field: string) => `option-${field}-${initial.id ?? "new"}`

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setProcessing(true)

    router[method](action, { ...draft, ...extraParams }, {
      preserveScroll: true,
      onSuccess: () => onOpenChange(false),
      onError: setErrors,
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
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

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("color")}>Color</Label>
              <ColorPicker
                id={fieldId("color")}
                value={draft.color}
                onChange={(color) => setDraft({ ...draft, color })}
              />
            </div>

            {footnote}
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>{submitLabel}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
