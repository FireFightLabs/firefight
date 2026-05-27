import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import type { LifecycleStageWithStatuses } from "@/pages/settings/lib/types"
import { incidentStatusesPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export function AddStatusDialog({ stage }: { stage: LifecycleStageWithStatuses }) {
  const [open, setOpen] = useState(false)
  const form = useForm({ name: "", description: "", color: "#3B82F6", lifecycle_stage_key: stage.key })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.post(incidentStatusesPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <IconPlus className="size-4" />
          Add Status
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Status to {stage.name}</DialogTitle>
            <DialogDescription>
              Create a new status within the {stage.name.toLowerCase()} lifecycle stage.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-name-${stage.key}`}>Name</Label>
              <Input
                id={`status-name-${stage.key}`}
                placeholder="e.g. Mitigated"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-desc-${stage.key}`}>Description</Label>
              <Textarea
                id={`status-desc-${stage.key}`}
                placeholder="When should this status be used?"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-color-${stage.key}`}>Color</Label>
              <div className="flex items-center gap-2">
                <Input
                  id={`status-color-${stage.key}`}
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
              Create Status
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
