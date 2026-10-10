import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import { IconPlayerPlay, IconPlus, IconRadar } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { OptionsTable } from "@/components/options-table"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import {
  disableInvestigationCheckPath,
  enableInvestigationCheckPath,
  investigationCheckPath,
  investigationPath,
  runInvestigationCheckPath,
} from "@/lib/routes"
import { timeAgo } from "@/lib/time"
import type { InvestigationCheck } from "@/types/serializers"
import { CheckDialog, type CheckDialogState } from "@/pages/halon/components/monitoring/check-dialog"
import type { CheckChoice } from "@/pages/halon/components/monitoring/types"

interface ChecksCardProps {
  checks: InvestigationCheck[]
  kinds: CheckChoice[]
  cadences: CheckChoice[]
  canManage: boolean
}

function toggleEnabled(check: InvestigationCheck) {
  router.patch(check.enabled ? disableInvestigationCheckPath(check.id) : enableInvestigationCheckPath(check.id), {}, { preserveScroll: true })
}

function runNow(check: InvestigationCheck) {
  router.post(runInvestigationCheckPath(check.id), {}, { preserveScroll: true })
}

// How a check's latest run ended, in the words of a check rather than an investigation.
const RUN_WORDS: Record<string, string> = {
  pending: "Queued",
  running: "Running",
  succeeded: "Checked",
  failed: "Stopped",
  canceled: "Stopped",
}

function LastRun({ check }: { check: InvestigationCheck }) {
  const run = check.lastRun
  if (!run) {
    return <span className="text-fg-muted">Not run yet</span>
  }

  const status = RUN_WORDS[run.status] ?? run.status
  return (
    <Link href={investigationPath(run.id)} className="text-link hover:underline">
      {status} {timeAgo(run.at)}
    </Link>
  )
}

function RunNow({ check }: { check: InvestigationCheck }) {
  const button = (
    <Button variant="ghost" size="sm" disabled={Boolean(check.runBlockedReason)} onClick={() => runNow(check)}>
      <IconPlayerPlay className="size-3.5" />
      Run now
    </Button>
  )
  if (!check.runBlockedReason) {
    return button
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-block">{button}</span>
      </TooltipTrigger>
      <TooltipContent side="left" className="max-w-56">{check.runBlockedReason}</TooltipContent>
    </Tooltip>
  )
}

function deleteDescription(check: InvestigationCheck | null): string {
  if (!check) {
    return ""
  }
  return `${check.name} has not run yet, so no run or problem is lost. Halon stops looking at it at once.`
}

export function ChecksCard({ checks, kinds, cadences, canManage }: ChecksCardProps) {
  const [dialog, setDialog] = useState<CheckDialogState>(null)
  const [deleting, setDeleting] = useState<InvestigationCheck | null>(null)

  function openCreate() {
    setDialog({ mode: "create" })
  }

  function openEdit(check: InvestigationCheck) {
    setDialog({ mode: "edit", check })
  }

  function closeDialog() {
    setDialog(null)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(investigationCheckPath(deleting.id), { preserveScroll: true, onFinish: cancelDelete })
  }

  const header = (
    <CardHeader>
      <div className="flex items-center justify-between gap-4">
        <div>
          <CardTitle>Scheduled checks</CardTitle>
          <CardDescription className="mt-1">
            What Halon looks at on its own, and how often. Each run reads your connected tools and notes what will break if nobody acts.
          </CardDescription>
        </div>
        {canManage && (
          <Button size="sm" onClick={openCreate}>
            <IconPlus className="size-4" />
            Add check
          </Button>
        )}
      </div>
    </CardHeader>
  )

  const dialogElement = canManage && <CheckDialog state={dialog} onClose={closeDialog} kinds={kinds} cadences={cadences} />

  if (checks.length === 0) {
    return (
      <Card>
        {header}
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconRadar className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No scheduled checks yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Add a check such as Disk space every morning or Certificates every Monday, and Halon tells the owning team before it becomes an incident.
            </p>
            {canManage && (
              <Button size="sm" variant="outline" className="mt-4" onClick={openCreate}>
                <IconPlus className="size-3.5" />
                Add your first check
              </Button>
            )}
          </div>
        </CardContent>
        {dialogElement}
      </Card>
    )
  }

  return (
    <Card>
      {header}
      <CardContent className="p-0">
        <OptionsTable
          options={checks}
          nameHeader="Check"
          headers={
            <>
              <TableHead className="hidden md:table-cell">Looks at</TableHead>
              <TableHead className="hidden lg:table-cell">Schedule</TableHead>
              <TableHead>Last run</TableHead>
              {canManage && <TableHead className="w-28" />}
            </>
          }
          cells={(check) => (
            <>
              <TableCell className="hidden md:table-cell text-sm text-muted-foreground">{check.kindLabel}</TableCell>
              <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">{check.schedule}</TableCell>
              <TableCell className="text-sm"><LastRun check={check} /></TableCell>
              {canManage && <TableCell><RunNow check={check} /></TableCell>}
            </>
          )}
          onToggleEnabled={toggleEnabled}
          onEdit={openEdit}
          onDelete={setDeleting}
          readOnly={!canManage}
        />
      </CardContent>
      {dialogElement}

      {canManage && (
        <ConfirmDeleteDialog
          open={Boolean(deleting)}
          title={`Delete ${deleting?.name ?? "this check"}?`}
          description={deleteDescription(deleting)}
          onConfirm={confirmDelete}
          onCancel={cancelDelete}
        />
      )}
    </Card>
  )
}
