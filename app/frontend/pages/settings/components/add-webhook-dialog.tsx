import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { webhooksPath } from "@/lib/routes"
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
import { Separator } from "@/components/ui/separator"
import { Switch } from "@/components/ui/switch"
import { subscribableEvents } from "@/pages/settings/lib/webhook-events"

export function AddWebhookDialog() {
  const [open, setOpen] = useState(false)
  const [selectedEvents, setSelectedEvents] = useState<Set<string>>(new Set())
  const form = useForm<{ name: string; url: string; subscribed_events: string[] }>({
    name: "",
    url: "",
    subscribed_events: [],
  })

  const toggleEvent = (event: string) => {
    setSelectedEvents((prev) => {
      const next = new Set(prev)
      if (next.has(event)) next.delete(event)
      else next.add(event)
      return next
    })
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.transform(() => ({
      webhook: { name: form.data.name, url: form.data.url, subscribed_events: [...selectedEvents] },
    }))
    form.post(webhooksPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
        setSelectedEvents(new Set())
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <IconPlus className="size-4" />
          Add Webhook
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Webhook</DialogTitle>
            <DialogDescription>
              Configure a new webhook endpoint for your workspace.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="wh-name">Name</Label>
              <Input
                id="wh-name"
                placeholder="e.g. PagerDuty Sync"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="wh-url">Payload URL</Label>
              <Input
                id="wh-url"
                type="url"
                placeholder="https://example.com/webhooks"
                value={form.data.url}
                onChange={(e) => form.setData("url", e.target.value)}
              />
              {form.errors.url && (
                <p className="text-xs text-destructive">{form.errors.url}</p>
              )}
            </div>
            <Separator />
            <div className="flex flex-col gap-3">
              <div>
                <Label className="text-sm font-medium">Events</Label>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Trigger a call to the payload URL when:
                </p>
              </div>
              <div className="flex items-center gap-2 text-sm">
                <Button
                  variant="link"
                  size="sm"
                  type="button"
                  className="h-auto p-0 text-xs"
                  onClick={() => setSelectedEvents(new Set(subscribableEvents.map((e) => e.value)))}
                >
                  Enable all
                </Button>
                <span className="text-muted-foreground">·</span>
                <Button
                  variant="link"
                  size="sm"
                  type="button"
                  className="h-auto p-0 text-xs"
                  onClick={() => setSelectedEvents(new Set())}
                >
                  Disable all
                </Button>
              </div>
              <div className="grid gap-2 max-h-64 overflow-y-auto rounded-lg border p-3">
                {subscribableEvents.map((event) => (
                  <div key={event.value} className="flex items-center gap-3">
                    <Switch
                      id={`event-${event.value}`}
                      checked={selectedEvents.has(event.value)}
                      onCheckedChange={() => toggleEvent(event.value)}
                    />
                    <Label
                      htmlFor={`event-${event.value}`}
                      className="text-sm font-normal cursor-pointer"
                    >
                      {event.label}
                    </Label>
                  </div>
                ))}
              </div>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create Webhook
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
