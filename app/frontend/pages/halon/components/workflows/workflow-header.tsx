import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import { IconAlertTriangle, IconFlask, IconPlayerPlay, IconRocket, IconSend } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { askPublishWorkflowPath, disableWorkflowPath, enableWorkflowPath, halonWorkflowsPath, workflowPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"
import { formatWhen, stateLabel, stateTone } from "@/pages/halon/components/workflows/labels"
import { PublishDialog } from "@/pages/halon/components/workflows/publish-dialog"
import { RunDialog } from "@/pages/halon/components/workflows/run-dialog"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"
import { TestRunDialog } from "@/pages/halon/components/workflows/test-run-dialog"
import type { PublishRequestStanding } from "@/pages/halon/components/workflows/types"

type Open = "run" | "test" | "publish" | "delete" | null

// What the workflow is and what can be done with it: run, test, publish or ask an admin to, switch on or off, delete.
export function WorkflowHeader({
  workflow,
  canManage,
  publishRequest,
}: {
  workflow: WorkflowDetail
  canManage: boolean
  publishRequest: PublishRequestStanding
}) {
  const [open, setOpen] = useState<Open>(null)

  function close() {
    setOpen(null)
  }

  function toggleEnabled(checked: boolean) {
    router.patch(checked ? enableWorkflowPath(workflow.id) : disableWorkflowPath(workflow.id), {}, { preserveScroll: true })
  }

  function askAdmin() {
    router.post(askPublishWorkflowPath(workflow.id), {}, { preserveScroll: true })
  }

  function confirmDelete() {
    router.delete(workflowPath(workflow.id), { onFinish: close })
  }

  const triggerWords = workflow.showsDraft && workflow.shownTriggerWords ? workflow.shownTriggerWords : workflow.triggerWords
  const askReason = publishRequest.waiting ? "You asked the admins, who are told by direct message." : publishRequest.askBlockedReason ?? undefined

  return (
    <div className="flex flex-col gap-4">
      <Link href={halonWorkflowsPath()} className="text-sm text-muted-foreground hover:underline">Workflows</Link>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-xl font-semibold">{workflow.name}</h1>
            <StatusPill label={stateLabel(workflow.state)} tone={stateTone(workflow.state)} />
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            {triggerWords}
            {workflow.nextRunAt && `. Next run ${formatWhen(workflow.nextRunAt)}`}
          </p>
          {workflow.description && <p className="mt-2 max-w-prose text-sm text-fg-secondary">{workflow.description}</p>}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Blocked reason={workflow.runBlockedReason} side="bottom">
            <Button size="sm" variant="outline" disabled={Boolean(workflow.runBlockedReason)} onClick={() => setOpen("run")}>
              <IconPlayerPlay className="size-4" />
              Run
            </Button>
          </Blocked>
          <Button size="sm" variant="outline" onClick={() => setOpen("test")}>
            <IconFlask className="size-4" />
            Test run
          </Button>
          {canManage ? (
            <Blocked reason={workflow.publishBlockedReason} side="bottom">
              <Button size="sm" disabled={Boolean(workflow.publishBlockedReason)} onClick={() => setOpen("publish")}>
                <IconRocket className="size-4" />
                Publish
              </Button>
            </Blocked>
          ) : (
            <Blocked reason={askReason} side="bottom">
              <Button size="sm" disabled={Boolean(askReason)} onClick={askAdmin}>
                <IconSend className="size-4" />
                {publishRequest.waiting ? "Asked an admin to publish" : "Ask an admin to publish"}
              </Button>
            </Blocked>
          )}
          {canManage && workflow.liveNumber && (
            <label className="flex items-center gap-2 text-sm">
              <Switch checked={workflow.enabled} onCheckedChange={toggleEnabled} aria-label={workflow.enabled ? "Turn off" : "Turn on"} />
              {workflow.enabled ? "On" : "Off"}
            </label>
          )}
          {canManage && (
            <Blocked reason={workflow.deletionBlockedReason} side="bottom">
              <Button size="sm" variant="ghost" className="text-destructive" disabled={Boolean(workflow.deletionBlockedReason)} onClick={() => setOpen("delete")}>
                Delete
              </Button>
            </Blocked>
          )}
        </div>
      </div>
      {workflow.freezeWarning && (
        <Alert>
          <IconAlertTriangle className="size-4" />
          <AlertDescription>{workflow.freezeWarning}</AlertDescription>
        </Alert>
      )}
      {workflow.triggerRefusal && (
        <Alert variant="destructive">
          <IconAlertTriangle className="size-4" />
          <AlertDescription>
            Its last start {workflow.triggerRefusedAt && `on ${formatWhen(workflow.triggerRefusedAt)} `}did not happen. {workflow.triggerRefusal}
          </AlertDescription>
        </Alert>
      )}

      <RunDialog target={open === "run" ? workflow : null} onClose={close} />
      <TestRunDialog key={`test-${open === "test"}`} workflow={workflow} open={open === "test"} onClose={close} />
      <PublishDialog workflow={workflow} open={open === "publish"} onClose={close} />
      <ConfirmDeleteDialog
        open={open === "delete"}
        title={`Delete ${workflow.name}?`}
        description={`${workflow.name} has never run, so no run is lost. Its draft, its versions and its own identity go with it.`}
        onConfirm={confirmDelete}
        onCancel={close}
      />
    </div>
  )
}
