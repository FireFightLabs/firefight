import {
  IconCircleCheck,
  IconCircleX,
  IconWebhook,
} from "@tabler/icons-react"
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
import { WebhookDetailSheet } from "@/pages/settings/components/webhooks/webhook-detail-sheet"

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
