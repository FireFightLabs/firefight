import { router, useForm } from "@inertiajs/react"
import { type FormEvent } from "react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { incidentTypePath, incidentTypesPath } from "@/lib/routes"
import { useSyncFormData } from "@/pages/settings/hooks/use-sync-form-data"
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

const DEFAULT_TYPE_COLOR = "#3B82F6"

interface TypeDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  type?: IncidentTypeSettings | null
}

function typeToFormData(type?: IncidentTypeSettings | null) {
  return {
    name: type?.name ?? "",
    description: type?.description ?? "",
    color: type?.color ?? DEFAULT_TYPE_COLOR,
  }
}

export function TypeDialog({ open, onOpenChange, type }: TypeDialogProps) {
  const isEdit = Boolean(type)
  const form = useForm(typeToFormData(type))

  useSyncFormData(type?.id, form, () => typeToFormData(type))

  function handleSubmit(e: FormEvent) {
    e.preventDefault()

    if (type) {
      router.patch(incidentTypePath(type.id), form.data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    } else {
      router.post(incidentTypesPath(), form.data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit incident type" : "Add incident type"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update the name, description, or color. The default is set from the list."
              : "Create a new incident type for your workspace."}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit}>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label htmlFor="type-name">Name</Label>
              <Input
                id="type-name"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
                placeholder="e.g. Outage, Degradation, Security"
              />
              {form.errors.name && <p className="text-xs text-destructive">{form.errors.name}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="type-description">Description</Label>
              <Textarea
                id="type-description"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
                placeholder="When should this type be used?"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="type-color">Color</Label>
              <ColorPicker
                id="type-color"
                value={form.data.color}
                onChange={(color) => form.setData("color", color)}
              />
            </div>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              {isEdit ? "Save changes" : "Create type"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
