import { useState, type ReactNode } from "react"
import { Link, router } from "@inertiajs/react"
import { IconPlayerPlay, IconRoute } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { OptionsTable } from "@/components/options-table"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { disableWorkflowPath, enableWorkflowPath, workflowPath } from "@/lib/routes"
import { WORKFLOW_RUN_QUERY_PARAM } from "@/lib/generated/constants"
import { timeAgo } from "@/lib/time"
import type { WorkflowRow } from "@/types/serializers"
import { formatWhen, runStatusLabel, stateLabel, stateTone } from "@/pages/halon/components/workflows/labels"
import { RunDialog, type RunTarget } from "@/pages/halon/components/workflows/run-dialog"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"

function toggleEnabled(workflow: WorkflowRow) {
  router.patch(workflow.enabled ? disableWorkflowPath(workflow.id) : enableWorkflowPath(workflow.id), {}, { preserveScroll: true })
}

function openWorkflow(workflow: WorkflowRow) {
  router.visit(workflowPath(workflow.id))
}

function LastRun({ workflow }: { workflow: WorkflowRow }) {
  const run = workflow.lastRun
  if (!run) {
    return <span className="text-muted-foreground">Not run yet</span>
  }

  return (
    <Link href={workflowPath(workflow.id, { [WORKFLOW_RUN_QUERY_PARAM]: run.id })} className="text-link hover:underline">
      {runStatusLabel(run.status)} {timeAgo(run.at)}
      {run.test && " (test)"}
    </Link>
  )
}

function deleteDescription(workflow: WorkflowRow | null): string {
  if (!workflow) {
    return ""
  }
  return `${workflow.name} has never run, so no run is lost. Its draft, its versions and its own identity go with it.`
}

export function WorkflowsCard({ workflows, canManage, action }: { workflows: WorkflowRow[]; canManage: boolean; action: ReactNode }) {
  const [running, setRunning] = useState<RunTarget | null>(null)
  const [deleting, setDeleting] = useState<WorkflowRow | null>(null)

  function closeRun() {
    setRunning(null)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(workflowPath(deleting.id), { preserveScroll: true, onFinish: cancelDelete })
  }

  const header = (
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <CardTitle>Workflows</CardTitle>
          <CardDescription className="mt-1">
            What runs on a schedule, once at a time or when someone presses Run. Each acts as its own identity, with only what an admin granted it.
          </CardDescription>
        </div>
        {action}
      </div>
    </CardHeader>
  )

  if (workflows.length === 0) {
    return (
      <Card>
        {header}
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconRoute className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No workflows yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Start one from the library, or ask Halon in a chat, such as &quot;in 30 minutes check web&quot;.
            </p>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      {header}
      <CardContent className="p-0">
        <OptionsTable
          options={workflows}
          nameHeader="Workflow"
          headers={
            <>
              <TableHead>State</TableHead>
              <TableHead className="hidden md:table-cell">Starts</TableHead>
              <TableHead className="hidden lg:table-cell">Next run</TableHead>
              <TableHead className="hidden sm:table-cell">Last run</TableHead>
              <TableHead className="w-24" />
            </>
          }
          cells={(workflow) => (
            <>
              <TableCell><StatusPill label={stateLabel(workflow.state)} tone={stateTone(workflow.state)} /></TableCell>
              <TableCell className="hidden md:table-cell whitespace-normal text-sm text-muted-foreground">{workflow.triggerWords}</TableCell>
              <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">{workflow.nextRunAt ? formatWhen(workflow.nextRunAt) : "-"}</TableCell>
              <TableCell className="hidden sm:table-cell text-sm"><LastRun workflow={workflow} /></TableCell>
              <TableCell>
                <Blocked reason={workflow.runBlockedReason}>
                  <Button variant="ghost" size="sm" disabled={Boolean(workflow.runBlockedReason)} onClick={() => setRunning(workflow)}>
                    <IconPlayerPlay className="size-3.5" />
                    Run
                  </Button>
                </Blocked>
              </TableCell>
            </>
          )}
          onSelect={openWorkflow}
          onToggleEnabled={toggleEnabled}
          onEdit={openWorkflow}
          onDelete={setDeleting}
          readOnly={!canManage}
        />
      </CardContent>
      <RunDialog target={running} onClose={closeRun} />
      {canManage && (
        <ConfirmDeleteDialog
          open={Boolean(deleting)}
          title={`Delete ${deleting?.name ?? "this workflow"}?`}
          description={deleteDescription(deleting)}
          onConfirm={confirmDelete}
          onCancel={cancelDelete}
        />
      )}
    </Card>
  )
}
