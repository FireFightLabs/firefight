import {
  IconCircleCheck,
  IconCircleX,
  IconWebhook,
} from "@tabler/icons-react"
import { useState } from "react"
import { router } from "@inertiajs/react"

import type { Webhook } from "@/types/serializers"
import { webhookPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AddWebhookDialog } from "@/pages/settings/components/webhooks/add-webhook-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { WebhookDetailSheet } from "@/pages/settings/components/webhooks/webhook-detail-sheet"
import { whenClosed } from "@/lib/handlers"

export function WebhooksTab({
  webhooks,
  canManage,
  activeWebhookId,
  onWebhookSelect,
}: {
  webhooks: Webhook[]
  canManage: boolean
  activeWebhookId: string | null
  onWebhookSelect: (id: string | null) => void
}) {
  const detailWebhook = activeWebhookId
    ? webhooks.find((webhook) => webhook.id === activeWebhookId) ?? null
    : null
  const [deleting, setDeleting] = useState<Webhook | null>(null)

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(webhookPath(deleting.id), { onFinish: () => setDeleting(null) })
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
            {canManage ? <AddWebhookDialog /> : null}
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
                    <TableCell onClick={(event) => event.stopPropagation()}>
                      {canManage ? (
                        <RowActions onEdit={() => onWebhookSelect(webhook.id)} onDelete={() => setDeleting(webhook)} />
                      ) : null}
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
      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this webhook"}?`}
        description={
          deleting && deleting.deliveryCount > 0
            ? `This also deletes ${deleting.deliveryCount} delivery ${deleting.deliveryCount === 1 ? "record" : "records"}, so the history of what was sent goes with it. Deactivate instead to stop deliveries and keep the log.`
            : "It stops receiving events straight away. No deliveries have been recorded yet, so nothing else is lost."
        }
        onConfirm={confirmDelete}
        onCancel={() => setDeleting(null)}
      />

      <WebhookDetailSheet
        webhook={detailWebhook}
        canManage={canManage}
        open={detailWebhook !== null}
        onOpenChange={whenClosed(() => onWebhookSelect(null))}
      />
    </div>
  )
}
