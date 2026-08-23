import { useState } from "react"
import { IconBellRinging, IconCheck, IconCopy, IconRoute } from "@tabler/icons-react"
import { Link, router } from "@inertiajs/react"

import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import { alertSourcePath, settingsAlertRoutingPath, settingsAlertsPath, tokenAlertSourcePath } from "@/lib/routes"
import { postJson } from "@/lib/http"
import { PROVIDER_LABELS } from "@/pages/settings/lib/alerts"
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AddSourceDialog } from "@/pages/settings/components/alert-sources/add-source-dialog"
import { EditSourceDialog } from "@/pages/settings/components/alert-sources/edit-source-dialog"
import { LastEventCell } from "@/pages/settings/components/alert-sources/last-event-cell"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"

export function AlertSourcesTab({
  alertSources,
  severities,
}: {
  alertSources: AlertSourceSettings[]
  severities: IncidentSeveritySettings[]
}) {
  const [editingSource, setEditingSource] = useState<AlertSourceSettings | null>(null)
  const [deletingSource, setDeletingSource] = useState<AlertSourceSettings | null>(null)
  const [copiedField, setCopiedField] = useState<string | null>(null)

  function markCopied(key: string) {
    setCopiedField(key)
    setTimeout(() => setCopiedField(null), 1500)
  }

  function handleCopy(value: string, key: string) {
    void navigator.clipboard.writeText(value).then(() => markCopied(key))
  }

  // The secret is fetched on demand so it never ships in page props.
  async function handleCopyToken(source: AlertSourceSettings) {
    try {
      const { ok, data } = await postJson<{ token: string }>(tokenAlertSourcePath(source.id))
      if (ok && data) {
        handleCopy(data.token, `token-${source.id}`)
      }
    } catch {
      // leave the button unchanged. The user can retry
    }
  }

  function confirmDelete() {
    if (!deletingSource) {
      return
    }
    router.delete(alertSourcePath(deletingSource.id))
    setDeletingSource(null)
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Alert sources</CardTitle>
              <CardDescription className="mt-1">
                Endpoints your monitoring tools POST alerts to. Each source has its own URL and secret token.
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <Button asChild variant="outline" size="sm">
                <Link href={settingsAlertsPath()}>
                  <IconBellRinging className="size-4" />
                  Recent alerts
                </Link>
              </Button>
              <Button asChild variant="outline" size="sm">
                <Link href={settingsAlertRoutingPath()}>
                  <IconRoute className="size-4" />
                  Routing rules
                </Link>
              </Button>
              <AddSourceDialog />
            </div>
          </div>
        </CardHeader>
        {alertSources.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Source</TableHead>
                  <TableHead className="hidden md:table-cell">Ingest URL</TableHead>
                  <TableHead className="hidden lg:table-cell">Token</TableHead>
                  <TableHead className="hidden w-40 lg:table-cell">Last received</TableHead>
                  <TableHead className="w-24 text-center">Status</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {alertSources.map((source) => (
                  <TableRow key={source.id}>
                    <TableCell>
                      <div className="flex items-center gap-2.5">
                        <IconBellRinging className="size-4 text-muted-foreground" />
                        <span className="font-medium">{source.name}</span>
                        <span className="text-xs text-muted-foreground/70">
                          {PROVIDER_LABELS[source.provider] ?? source.provider}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-7 gap-1.5 px-2 font-mono text-xs text-muted-foreground"
                        onClick={() => handleCopy(`${window.location.origin}${source.ingestPath}`, `url-${source.id}`)}
                      >
                        {copiedField === `url-${source.id}` ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
                        {source.ingestPath}
                      </Button>
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-7 gap-1.5 px-2 font-mono text-xs text-muted-foreground"
                        onClick={() => void handleCopyToken(source)}
                      >
                        {copiedField === `token-${source.id}` ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
                        Copy token
                      </Button>
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">
                      <LastEventCell source={source} />
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant={source.enabled ? "default" : "secondary"}>
                        {source.enabled ? "Enabled" : "Disabled"}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center justify-end gap-1">
                        <Button asChild variant="ghost" size="sm" className="h-7 gap-1.5 px-2 text-muted-foreground">
                          <Link href={settingsAlertsPath({ source_id: source.id })}>
                            <IconBellRinging className="size-3.5" />
                            Alerts
                          </Link>
                        </Button>
                        <Button asChild variant="ghost" size="sm" className="h-7 gap-1.5 px-2 text-muted-foreground">
                          <Link href={settingsAlertRoutingPath({ source_id: source.id })}>
                            <IconRoute className="size-3.5" />
                            Routing
                          </Link>
                        </Button>
                        <RowActions
                          onEdit={() => setEditingSource(source)}
                          onDelete={() => setDeletingSource(source)}
                        />
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <p className="text-sm text-muted-foreground">
              No alert sources yet. Add one to get an ingest URL for your monitoring tool.
            </p>
          </CardContent>
        )}
      </Card>

      {editingSource && (
        <EditSourceDialog
          source={editingSource}
          severities={severities}
          onClose={() => setEditingSource(null)}
        />
      )}

      <ConfirmDeleteDialog
        open={Boolean(deletingSource)}
        title={`Delete ${deletingSource?.name ?? "this source"}?`}
        description="Its ingest URL and token stop working immediately: anything still sending alerts here will be rejected. Its alerts and routing rules are deleted too."
        onConfirm={confirmDelete}
        onCancel={() => setDeletingSource(null)}
      />
    </div>
  )
}
