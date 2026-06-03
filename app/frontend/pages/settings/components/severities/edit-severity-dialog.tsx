import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import type { IncidentSeveritySettings } from "@/types/serializers"
import { incidentSeverityPath } from "@/lib/routes"
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

export function EditSeverityDialog({
  severity,
  open,
  onOpenChange,
}: {
  severity: IncidentSeveritySettings
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const form = useForm({ name: severity.name, description: severity.description ?? "", color: severity.color })
  const [prevOpen, setPrevOpen] = useState(open)
  if (open !== prevOpen) {
    setPrevOpen(open)
    if (open) {
      form.setData({ name: severity.name, description: severity.description ?? "", color: severity.color })
    }
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.patch(incidentSeverityPath(severity.id), {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit Severity</DialogTitle>
            <DialogDescription>
              Update the name and description for this severity level.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-name-${severity.id}`}>Name</Label>
              <Input
                id={`edit-sev-name-${severity.id}`}
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-desc-${severity.id}`}>Description</Label>
              <Textarea
                id={`edit-sev-desc-${severity.id}`}
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-color-${severity.id}`}>Color</Label>
              <div className="flex items-center gap-2">
                <Input
                  id={`edit-sev-color-${severity.id}`}
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
