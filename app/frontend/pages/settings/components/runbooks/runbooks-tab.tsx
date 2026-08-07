import { useState } from "react"
import { router } from "@inertiajs/react"
import {
  IconBook,
  IconExternalLink,
  IconPlus,
} from "@tabler/icons-react"

import type {
  IncidentSeveritySettings,
  IncidentTypeSettings,
  RunbookCustomField,
  RunbookSettings,
} from "@/types/serializers"
import { reorderRunbooksPath, disableRunbookPath, enableRunbookPath, runbookPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { RunbookDetailSheet } from "@/pages/settings/components/runbooks/runbook-detail-sheet"
import { RunbookDialog } from "@/pages/settings/components/runbooks/runbook-dialog"
import { attachSummary } from "@/pages/settings/lib/runbook-conditions"

interface RunbooksTabProps {
  runbooks: RunbookSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  customFields: RunbookCustomField[]
}

export function RunbooksTab({ runbooks, incidentTypes, severities, customFields }: RunbooksTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingRunbook, setEditingRunbook] = useState<RunbookSettings | null>(null)
  const [deleting, setDeleting] = useState<RunbookSettings | null>(null)
  const [viewing, setViewing] = useState<RunbookSettings | null>(null)



  function openCreate() {
    setEditingRunbook(null)
    setDialogOpen(true)
  }

  function openEdit(runbook: RunbookSettings) {
    setEditingRunbook(runbook)
    setDialogOpen(true)
  }

  const header = (
    <CardHeader>
      <div className="flex items-center justify-between">
        <div>
          <CardTitle>Runbooks</CardTitle>
          <CardDescription className="mt-1">
            Document response procedures and surface them automatically on matching incidents.
          </CardDescription>
        </div>
        <Button size="sm" onClick={openCreate}>
          <IconPlus className="size-4" />
          Add runbook
        </Button>
      </div>
    </CardHeader>
  )

  const dialog = (
    <RunbookDialog
      open={dialogOpen}
      onOpenChange={setDialogOpen}
      runbook={editingRunbook}
      incidentTypes={incidentTypes}
      severities={severities}
      customFields={customFields}
    />
  )

  if (runbooks.length === 0) {
    return (
      <Card>
        {header}
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconBook className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No runbooks yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Create runbooks like Database failover or Rollback deploy to give responders step-by-step guidance during incidents.
            </p>
            <Button size="sm" variant="outline" className="mt-4" onClick={openCreate}>
              <IconPlus className="size-3.5" />
              Create your first runbook
            </Button>
          </div>
        </CardContent>
        {dialog}
      </Card>
    )
  }

  return (
    <Card>
      {header}
      <CardContent className="p-0">
        <OptionsTable
          options={runbooks}
          nameHeader="Runbook"
          headers={
            <>
              <TableHead className="hidden lg:table-cell">Summary</TableHead>
              <TableHead className="hidden md:table-cell">Conditions</TableHead>
              <TableHead className="w-24 text-center">Incidents</TableHead>
            </>
          }
          cells={(runbook) => (
            <>
              <TableCell className="hidden lg:table-cell text-sm text-muted-foreground max-w-xs truncate">
                <span className="flex items-center gap-1.5">
                  {runbook.summary}
                  {runbook.externalUrl && (
                    <a
                      href={runbook.externalUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="shrink-0 text-muted-foreground hover:text-foreground"
                      aria-label={`Open ${runbook.name} runbook link`}
                    >
                      <IconExternalLink className="size-3.5" />
                    </a>
                  )}
                </span>
              </TableCell>
              <TableCell className="hidden md:table-cell text-sm text-muted-foreground max-w-sm truncate">
                {attachSummary(runbook, incidentTypes, severities, customFields)}
              </TableCell>
              <TableCell className="text-center">
                <Badge variant="outline" className="font-mono tabular-nums">{runbook.usageCount}</Badge>
              </TableCell>
            </>
          )}
          reorderPath={reorderRunbooksPath()}
          onToggleEnabled={(runbook) =>
            router.patch(
              runbook.enabled ? disableRunbookPath(runbook.id) : enableRunbookPath(runbook.id),
              {},
              { preserveScroll: true },
            )}
          onSelect={setViewing}
          onEdit={openEdit}
          onDelete={setDeleting}
        />
      </CardContent>
      {dialog}

      <RunbookDetailSheet
        runbook={viewing}
        incidentTypes={incidentTypes}
        severities={severities}
        customFields={customFields}
        open={Boolean(viewing)}
        onOpenChange={(next) => !next && setViewing(null)}
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this runbook"}?`}
        description="No incident references this runbook, so nothing loses its history. It stops matching new incidents straight away."
        onConfirm={() => {
          if (!deleting) {
            return
          }
          router.delete(runbookPath(deleting.id), { preserveScroll: true, onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
