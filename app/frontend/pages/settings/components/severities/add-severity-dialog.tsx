import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { incidentSeveritiesPath } from "@/lib/routes"
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
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export function AddSeverityDialog() {
  const [open, setOpen] = useState(false)
  const form = useForm({ name: "", description: "", color: "#FF6B35" })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.post(incidentSeveritiesPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <IconPlus className="size-4" />
          Add Severity
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Severity</DialogTitle>
            <DialogDescription>
              Create a new severity level for your workspace.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="sev-name">Name</Label>
              <Input
                id="sev-name"
                placeholder="e.g. Moderate"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="sev-desc">Description</Label>
              <Textarea
                id="sev-desc"
                placeholder="When should this severity be assigned?"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="sev-color">Color</Label>
              <ColorPicker
                id="sev-color"
                value={form.data.color}
                onChange={(color) => form.setData("color", color)}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              New severities are added at the bottom as the least severe. Drag to move it up the list.
            </p>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create Severity
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
