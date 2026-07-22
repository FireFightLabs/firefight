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
  RunbookSettings,
} from "@/types/serializers"
import { runbookPath } from "@/lib/routes"
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
import { RowActions } from "@/pages/settings/components/row-actions"
import { RunbookDialog } from "@/pages/settings/components/runbooks/runbook-dialog"
import { conditionSummary } from "@/pages/settings/lib/runbook-conditions"

interface RunbooksTabProps {
  runbooks: RunbookSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
}

export function RunbooksTab({ runbooks, incidentTypes, severities }: RunbooksTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingRunbook, setEditingRunbook] = useState<RunbookSettings | null>(null)

  function handleDelete(runbook: RunbookSettings) {
    router.delete(runbookPath(runbook.id), { preserveScroll: true })
  }

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
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead>Runbook</TableHead>
              <TableHead className="hidden md:table-cell">Conditions</TableHead>
              <TableHead className="w-20 text-center">Steps</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {runbooks.map((runbook) => {
              const summary = conditionSummary(runbook.conditions ?? [], incidentTypes, severities)

              return (
                <TableRow key={runbook.id}>
                  <TableCell>
                    <div className="flex items-center gap-2.5">
                      <span className="font-medium">{runbook.name}</span>
                      {runbook.externalUrl && (
                        <a
                          href={runbook.externalUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-muted-foreground hover:text-foreground"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <IconExternalLink className="size-3.5" />
                        </a>
                      )}
                    </div>
                    {runbook.summary && (
                      <p className="mt-0.5 max-w-md truncate text-sm text-muted-foreground">{runbook.summary}</p>
                    )}
                  </TableCell>
                  <TableCell className="hidden md:table-cell text-sm text-muted-foreground max-w-sm truncate">
                    {summary ?? "Always shown"}
                  </TableCell>
                  <TableCell className="text-center">
                    <Badge variant="outline" className="font-mono tabular-nums">
                      {runbook.steps.length}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <RowActions
                      onEdit={() => openEdit(runbook)}
                      onDelete={() => handleDelete(runbook)}
                    />
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </CardContent>
      {dialog}
    </Card>
  )
}
