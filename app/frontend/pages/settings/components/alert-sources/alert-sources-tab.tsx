import { useState } from "react"
import { IconBellRinging, IconCheck, IconCopy, IconRoute } from "@tabler/icons-react"
import { Link, router } from "@inertiajs/react"

import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import { alertSourcePath, settingsAlertRoutingPath, settingsAlertsPath, tokenAlertSourcePath } from "@/lib/routes"
import { postJson } from "@/lib/http"
import { providerLabel, type AlertProviderSetup } from "@/pages/settings/lib/alerts"
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
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { RowActions } from "@/components/row-actions"

export function AlertSourcesTab({
  alertSources,
  severities,
  providers,
  setupSourceId,
  canManage,
}: {
  alertSources: AlertSourceSettings[]
  severities: IncidentSeveritySettings[]
  providers: AlertProviderSetup[]
  setupSourceId: string | null
  canManage: boolean
}) {
  const [editingSource, setEditingSource] = useState<AlertSourceSettings | null>(null)
  // A source just created opens on its setup, since pointing the tool at it is the next step. Creating stays on this
  // page, so the setup opens when the id arrives rather than only on the first render.
  const [setupOpenedFor, setSetupOpenedFor] = useState<string | null>(null)
  if (setupSourceId && setupSourceId !== setupOpenedFor) {
    setSetupOpenedFor(setupSourceId)
    setEditingSource(alertSources.find((source) => source.id === setupSourceId) ?? null)
  }
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
      // The button stays as it was and the user can retry.
    }
  }

  function secretFromProvider(source: AlertSourceSettings) {
    return providers.find((entry) => entry.provider === source.provider)?.secretFromProvider ?? false
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
              {canManage && <AddSourceDialog providers={providers} />}
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
                  {canManage && <TableHead className="hidden lg:table-cell">Token</TableHead>}
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
                        <span className="text-xs text-fg-muted">
                          {providerLabel(providers, source.provider)}
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
                    {canManage && (
                      <TableCell className="hidden lg:table-cell">
                        {secretFromProvider(source) ? (
                          <span className="px-2 text-xs text-muted-foreground">
                            {source.secretSummary ? "Secret saved" : "No secret yet"}
                          </span>
                        ) : (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-7 gap-1.5 px-2 font-mono text-xs text-muted-foreground"
                            onClick={() => void handleCopyToken(source)}
                          >
                            {copiedField === `token-${source.id}` ? <IconCheck className="size-3.5" /> : <IconCopy className="size-3.5" />}
                            Copy token
                          </Button>
                        )}
                      </TableCell>
                    )}
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
                        {canManage && (
                          <RowActions
                            onEdit={() => setEditingSource(source)}
                            onDelete={() => setDeletingSource(source)}
                          />
                        )}
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

      {canManage && editingSource && (
        <EditSourceDialog
          source={editingSource}
          severities={severities}
          setup={providers.find((entry) => entry.provider === editingSource.provider) ?? null}
          onClose={() => setEditingSource(null)}
        />
      )}

      {canManage && (
        <ConfirmDeleteDialog
          open={Boolean(deletingSource)}
          title={`Delete ${deletingSource?.name ?? "this source"}?`}
          description="Its ingest URL and token stop working immediately: anything still sending alerts here will be rejected. Its alerts and routing rules are deleted too."
          onConfirm={confirmDelete}
          onCancel={() => setDeletingSource(null)}
        />
      )}
    </div>
  )
}
