import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"
import { IconCircleCheck, IconCircleX } from "@tabler/icons-react"

import type { Webhook } from "@/types/serializers"
import {
  activateWebhookPath,
  deactivateWebhookPath,
  testWebhookPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { eventLabel } from "@/pages/settings/lib/webhook-events"

export function WebhookDetailSheet({
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
