import { router, useForm } from "@inertiajs/react"
import { type FormEvent } from "react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { incidentTypePath, incidentTypesPath } from "@/lib/routes"
import { useSyncFormData } from "@/pages/settings/hooks/use-sync-form-data"
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
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"

const TYPE_COLORS = [
  "#3B82F6", "#8B5CF6", "#10B981", "#F59E0B", "#EF4444", "#06B6D4",
  "#EC4899", "#6366F1", "#14B8A6", "#F97316",
]

interface TypeDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  type?: IncidentTypeSettings | null
}

function typeToFormData(type?: IncidentTypeSettings | null) {
  return {
    name: type?.name ?? "",
    description: type?.description ?? "",
    color: type?.color ?? TYPE_COLORS[0],
    is_default: type?.isDefault ?? false,
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
              ? "Update the name, description, color, or default status."
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
              <Label>Color</Label>
              <div className="flex flex-wrap gap-1.5">
                {TYPE_COLORS.map((c) => (
                  <button
                    key={c}
                    type="button"
                    className={`size-7 rounded-md transition-all ${
                      form.data.color === c
                        ? "ring-2 ring-offset-2 ring-offset-background ring-foreground scale-110"
                        : "hover:scale-105"
                    }`}
                    style={{ backgroundColor: c }}
                    onClick={() => form.setData("color", c)}
                  />
                ))}
              </div>
            </div>

            <div className="flex items-center gap-3">
              <Switch
                id="type-default"
                checked={form.data.is_default}
                onCheckedChange={(checked) => form.setData("is_default", checked)}
              />
              <Label htmlFor="type-default" className="cursor-pointer">Default type</Label>
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
