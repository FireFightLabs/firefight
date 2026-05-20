import {
  IconCircleCheck,
  IconCircleX,
  IconPlus,
  IconWebhook,
} from "@tabler/icons-react"
import { useEffect, useState, type FormEvent } from "react"
import { router, useForm } from "@inertiajs/react"

import type { Webhook } from "@/types/serializers"
import {
  webhooksPath,
  webhookPath,
  activateWebhookPath,
  deactivateWebhookPath,
  testWebhookPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
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
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { RowActions } from "./shared"

const subscribableEvents = [
  { value: "incident.created", label: "Incident created" },
  { value: "incident.updated", label: "Incident updated" },
  { value: "incident.resolved", label: "Incident resolved" },
  { value: "incident.reopened", label: "Incident reopened" },
  { value: "incident.escalated", label: "Incident escalated" },
  { value: "lead.assigned", label: "Lead assigned" },
  { value: "action.created", label: "Action created" },
  { value: "action.picked_up", label: "Action picked up" },
  { value: "action.completed", label: "Action completed" },
  { value: "postmortem.generated", label: "Postmortem generated" },
  { value: "relationship.created", label: "Relationship created" },
  { value: "incident.marked_duplicate", label: "Incident marked duplicate" },
  { value: "incident.merged_into", label: "Incident merged into" },
] as const

const eventLabel = (value: string) =>
  subscribableEvents.find((e) => e.value === value)?.label ?? value

function AddWebhookDialog() {
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

function WebhookDetailSheet({
  webhook,
  open,
  onOpenChange,
}: {
  webhook: Webhook | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [secretVisible, setSecretVisible] = useState(false)

  useEffect(() => {
    if (!open) setSecretVisible(false)
  }, [open])

  if (!webhook) return null

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <div className="flex items-center gap-2">
            <SheetTitle>{webhook.name}</SheetTitle>
            {webhook.active ? (
              <Badge variant="secondary" className="gap-1 bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                <IconCircleCheck className="size-3" />
                Active
              </Badge>
            ) : (
              <Badge variant="secondary" className="gap-1">
                <IconCircleX className="size-3" />
                Inactive
              </Badge>
            )}
          </div>
          <SheetDescription className="font-mono text-xs break-all">
            {webhook.url}
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-6 pb-6">
          <div className="flex items-center gap-2">
            {webhook.active ? (
              <Button
                variant="outline"
                size="sm"
                onClick={() => router.post(deactivateWebhookPath(webhook.id))}
              >
                Deactivate
              </Button>
            ) : (
              <Button
                variant="outline"
                size="sm"
                onClick={() => router.post(activateWebhookPath(webhook.id))}
              >
                Activate
              </Button>
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={() => router.post(testWebhookPath(webhook.id))}
            >
              Send Test
            </Button>
          </div>

          <div className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Signing Secret
            </h4>
            <div className="flex items-center gap-2">
              <code className="flex-1 rounded-md bg-muted px-3 py-2 font-mono text-sm break-all">
                {secretVisible ? webhook.signingSecret : "••••••••••••••••••••••••••"}
              </code>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setSecretVisible(!secretVisible)}
              >
                {secretVisible ? "Hide" : "Reveal"}
              </Button>
            </div>
          </div>

          <Separator />

          <div className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Subscribed Events
            </h4>
            <div className="flex flex-wrap gap-1.5">
              {webhook.subscribedEvents.map((event) => (
                <Badge key={event} variant="outline" className="text-xs">
                  {eventLabel(event)}
                </Badge>
              ))}
            </div>
          </div>

          <Separator />

          <div className="flex flex-col gap-3">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Recent Deliveries
            </h4>
            {webhook.deliveries.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                This webhook hasn't been triggered yet.
              </p>
            ) : (
              <div className="rounded-lg border overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent">
                      <TableHead>Event</TableHead>
                      <TableHead className="w-20 text-center">Status</TableHead>
                      <TableHead className="w-28 text-right">Delivered</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {webhook.deliveries.map((delivery) => {
                      const succeeded =
                        delivery.state === "completed" &&
                        delivery.responseCode !== null &&
                        delivery.responseCode !== undefined &&
                        delivery.responseCode >= 200 &&
                        delivery.responseCode < 300
                      return (
                        <TableRow key={delivery.id}>
                          <TableCell>
                            <div className="flex flex-col gap-0.5">
                              <span className="text-sm">{eventLabel(delivery.eventType)}</span>
                              {!succeeded && delivery.errorMessage && (
                                <span className="text-xs text-red-500 dark:text-red-400">
                                  {delivery.errorMessage}
                                </span>
                              )}
                            </div>
                          </TableCell>
                          <TableCell className="text-center">
                            {succeeded ? (
                              <Badge variant="secondary" className="gap-1 bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 text-xs">
                                {delivery.responseCode}
                              </Badge>
                            ) : (
                              <Badge variant="secondary" className="gap-1 bg-red-500/15 text-red-600 dark:text-red-400 text-xs">
                                {delivery.responseCode ?? "ERR"}
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell className="text-right text-xs text-muted-foreground">
                            {new Date(delivery.deliveredAt).toLocaleDateString("en-US", {
                              month: "short",
                              day: "numeric",
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}

export function WebhooksTab({
  webhooks,
  activeWebhookId,
  onWebhookSelect,
}: {
  webhooks: Webhook[]
  activeWebhookId: string | null
  onWebhookSelect: (id: string | null) => void
}) {
  const detailWebhook = activeWebhookId
    ? webhooks.find((w) => w.id === activeWebhookId) ?? null
    : null

  function handleDelete(webhook: Webhook) {
    router.delete(webhookPath(webhook.id))
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Webhooks</CardTitle>
              <CardDescription className="mt-1">
                Send real-time notifications to external services when incident events occur.
              </CardDescription>
            </div>
            <AddWebhookDialog />
          </div>
        </CardHeader>
        {webhooks.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Webhook</TableHead>
                  <TableHead className="hidden md:table-cell">URL</TableHead>
                  <TableHead className="w-24 text-center">Events</TableHead>
                  <TableHead className="w-24 text-center">Status</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {webhooks.map((webhook) => (
                  <TableRow key={webhook.id} className="cursor-pointer" onClick={() => onWebhookSelect(webhook.id)}>
                    <TableCell>
                      <div className="flex items-center gap-2.5">
                        <IconWebhook className="size-4 text-muted-foreground" />
                        <span className="font-medium">{webhook.name}</span>
                      </div>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      <span className="font-mono text-xs text-muted-foreground truncate block max-w-xs">
                        {webhook.url}
                      </span>
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant="outline" className="tabular-nums">
                        {webhook.subscribedEvents.length}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-center">
                      {webhook.active ? (
                        <Badge variant="secondary" className="gap-1 bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                          <IconCircleCheck className="size-3" />
                          Active
                        </Badge>
                      ) : (
                        <Badge variant="secondary" className="gap-1">
                          <IconCircleX className="size-3" />
                          Inactive
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell onClick={(e) => e.stopPropagation()}>
                      <RowActions onEdit={() => onWebhookSelect(webhook.id)} onDelete={() => handleDelete(webhook)} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <p className="text-sm text-muted-foreground text-center py-8">
              No webhooks configured yet.
            </p>
          </CardContent>
        )}
      </Card>
      <WebhookDetailSheet
        webhook={detailWebhook}
        open={detailWebhook !== null}
        onOpenChange={(open) => { if (!open) onWebhookSelect(null) }}
      />
    </div>
  )
}
