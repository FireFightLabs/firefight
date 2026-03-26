import {
  IconCircleCheck,
  IconCircleX,
  IconPlus,
  IconWebhook,
} from "@tabler/icons-react"
import * as React from "react"

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

import type { Webhook } from "@/modules/settings/types"
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

const mockWebhooks: Webhook[] = [
  {
    id: "1",
    name: "PagerDuty Sync",
    url: "https://events.pagerduty.com/webhooks/firefight",
    active: true,
    signingSecret: "whsec_RHqtWsrCGAkGGNK53ff4qsJP",
    subscribedEvents: ["incident.created", "incident.resolved", "incident.escalated"],
    createdAt: "2026-02-15T10:00:00Z",
    deliveries: [
      { id: "d1", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-25T08:15:02Z" },
      { id: "d2", eventType: "incident.resolved", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-24T15:45:05Z" },
      { id: "d3", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-24T14:20:01Z" },
      { id: "d4", eventType: "incident.escalated", state: "errored", responseCode: 503, errorMessage: "Service unavailable", deliveredAt: "2026-03-23T11:00:03Z" },
      { id: "d5", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-22T19:30:01Z" },
    ],
  },
  {
    id: "2",
    name: "Datadog Events",
    url: "https://api.datadoghq.com/api/v1/events",
    active: true,
    signingSecret: "whsec_9xMkPqB7vTnWjL2sYhR6dE4f",
    subscribedEvents: ["incident.created", "incident.updated", "incident.resolved", "lead.assigned"],
    createdAt: "2026-03-01T14:30:00Z",
    deliveries: [
      { id: "d6", eventType: "incident.updated", state: "completed", responseCode: 202, errorMessage: null, deliveredAt: "2026-03-25T09:00:01Z" },
      { id: "d7", eventType: "incident.created", state: "completed", responseCode: 202, errorMessage: null, deliveredAt: "2026-03-25T08:15:01Z" },
    ],
  },
  {
    id: "3",
    name: "Internal Analytics",
    url: "https://analytics.internal.io/hooks/incidents",
    active: false,
    signingSecret: "whsec_Lm3nKp8vQwXy5Zt2Aj7BcD9f",
    subscribedEvents: ["incident.created", "incident.resolved", "postmortem.generated"],
    createdAt: "2026-01-20T09:00:00Z",
    deliveries: [],
  },
]

function WebhookDetailSheet({
  webhook,
  open,
  onOpenChange,
}: {
  webhook: Webhook | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [secretVisible, setSecretVisible] = React.useState(false)

  if (!webhook) return null

  const eventLabel = (value: string) =>
    subscribableEvents.find((e) => e.value === value)?.label ?? value

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
            <p className="text-xs text-muted-foreground">
              We send a <code className="text-xs">X-Webhook-Signature</code> header with each request.
              Generate a HMAC using SHA256 of the request body with this secret to verify authenticity.
            </p>
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
  activeWebhookId,
  onWebhookSelect,
}: {
  activeWebhookId: string | null
  onWebhookSelect: (id: string | null) => void
}) {
  const [selectedEvents, setSelectedEvents] = React.useState<Set<string>>(new Set())
  const detailWebhook = activeWebhookId
    ? mockWebhooks.find((w) => w.id === activeWebhookId) ?? null
    : null

  const toggleEvent = (event: string) => {
    setSelectedEvents((prev) => {
      const next = new Set(prev)
      if (next.has(event)) next.delete(event)
      else next.add(event)
      return next
    })
  }

  const enableAll = () => {
    setSelectedEvents(new Set(subscribableEvents.map((e) => e.value)))
  }

  const disableAll = () => {
    setSelectedEvents(new Set())
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
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm">
                  <IconPlus className="size-4" />
                  Add Webhook
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-lg">
                <DialogHeader>
                  <DialogTitle>Add Webhook</DialogTitle>
                  <DialogDescription>
                    Configure a new webhook endpoint for your workspace.
                  </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-4 py-2">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="wh-name">Name</Label>
                    <Input id="wh-name" placeholder="e.g. PagerDuty Sync" />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="wh-url">Payload URL</Label>
                    <Input id="wh-url" type="url" placeholder="https://example.com/webhooks" />
                    <p className="text-xs text-muted-foreground">
                      The URL that will receive webhook POST requests.
                    </p>
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
                        className="h-auto p-0 text-xs"
                        onClick={enableAll}
                      >
                        Enable all
                      </Button>
                      <span className="text-muted-foreground">·</span>
                      <Button
                        variant="link"
                        size="sm"
                        className="h-auto p-0 text-xs"
                        onClick={disableAll}
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
                    <Button variant="outline">Cancel</Button>
                  </DialogClose>
                  <Button>Create Webhook</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>
        </CardHeader>
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
              {mockWebhooks.map((webhook) => (
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
                  <TableCell>
                    <RowActions onEdit={() => {}} onDelete={() => {}} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <WebhookDetailSheet
        webhook={detailWebhook}
        open={detailWebhook !== null}
        onOpenChange={(open) => { if (!open) onWebhookSelect(null) }}
      />
    </div>
  )
}
