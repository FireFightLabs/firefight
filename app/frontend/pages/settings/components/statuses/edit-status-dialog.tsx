import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import type { IncidentStatusSettings } from "@/types/serializers"
import { incidentStatusPath } from "@/lib/routes"
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

export function EditStatusDialog({
  status,
  open,
  onOpenChange,
}: {
  status: IncidentStatusSettings
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const form = useForm({ name: status.name, description: status.description ?? "", color: status.color })
  const [prevOpen, setPrevOpen] = useState(open)
  if (open !== prevOpen) {
    setPrevOpen(open)
    if (open) {
      form.setData({ name: status.name, description: status.description ?? "", color: status.color })
    }
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.patch(incidentStatusPath(status.id), {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit Status</DialogTitle>
            <DialogDescription>
              Update the name and description for this status.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-name-${status.id}`}>Name</Label>
              <Input
                id={`edit-name-${status.id}`}
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-desc-${status.id}`}>Description</Label>
              <Textarea
                id={`edit-desc-${status.id}`}
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-color-${status.id}`}>Color</Label>
              <div className="flex items-center gap-2">
                <Input
                  id={`edit-color-${status.id}`}
                  type="color"
                  value={form.data.color}
                  onChange={(e) => form.setData("color", e.target.value)}
                  className="h-9 w-12 cursor-pointer p-1"
                />
                <Input
                  value={form.data.color}
                  onChange={(e) => form.setData("color", e.target.value)}
                  className="flex-1 font-mono text-sm"
                  placeholder="#3B82F6"
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Save Changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
