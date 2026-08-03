import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { alertSourcesPath } from "@/lib/routes"
import { PROVIDER_LABELS } from "@/pages/settings/lib/alerts"
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"


export function AddSourceDialog() {
  const [open, setOpen] = useState(false)
  const form = useForm<{ name: string; provider: string }>({ name: "", provider: "generic" })

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    form.transform(() => ({ alert_source: { name: form.data.name, provider: form.data.provider } }))
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
          Add source
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
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="source-name">Name</Label>
              <Input
                id="source-name"
                value={form.data.name}
                onChange={(event) => form.setData("name", event.target.value)}
                placeholder="e.g. Northflank production"
                autoFocus
              />
              {form.errors.name && <p className="text-sm text-destructive">{form.errors.name}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <Label>Provider</Label>
              <Select value={form.data.provider} onValueChange={(value) => form.setData("provider", value)}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(PROVIDER_LABELS).map(([value, label]) => (
                    <SelectItem key={value} value={value}>{label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
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
