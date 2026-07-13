import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { alertSourcesPath } from "@/lib/routes"
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

export function AddSourceDialog() {
  const [open, setOpen] = useState(false)
  const form = useForm<{ name: string }>({ name: "" })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.transform(() => ({ alert_source: { name: form.data.name } }))
    form.post(alertSourcesPath(), {
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
          Add Source
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add alert source</DialogTitle>
            <DialogDescription>
              Creates a unique ingest URL and secret token for one monitoring tool.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 py-4">
            <Label htmlFor="source-name">Name</Label>
            <Input
              id="source-name"
              value={form.data.name}
              onChange={(e) => form.setData("name", e.target.value)}
              placeholder="e.g. Grafana production"
              autoFocus
            />
            {form.errors.name && <p className="text-sm text-destructive">{form.errors.name}</p>}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing || !form.data.name.trim()}>
              Create source
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
