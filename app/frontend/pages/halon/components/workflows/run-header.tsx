import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import { IconAlertTriangle, IconPin, IconPinnedOff, IconPlayerStop } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { cancelWorkflowRunPath, pinWorkflowRunPath, unpinWorkflowRunPath, workflowPath } from "@/lib/routes"
import type { WorkflowRun } from "@/types/serializers"
import { dollars, formatWhen, runStatusLabel, runTone } from "@/pages/halon/components/workflows/labels"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"

function spentWords(run: WorkflowRun): string {
  const spent = dollars(run.aiSpentCents)
  return run.costCapCents ? `${spent} of its ${dollars(run.costCapCents)} AI ceiling` : `${spent} of AI, with no ceiling`
}

// The run in a line or two: how it went, who started it, who it acted as, what it spent, and what can be done with it.
export function RunHeader({ run, canManage }: { run: WorkflowRun; canManage: boolean }) {
  const [stopping, setStopping] = useState(false)

  function pin() {
    router.patch(run.pinned ? unpinWorkflowRunPath(run.workflowId, run.id) : pinWorkflowRunPath(run.workflowId, run.id), {}, { preserveScroll: true })
  }

  function cancelStop() {
    setStopping(false)
  }

  function stop() {
    router.post(cancelWorkflowRunPath(run.workflowId, run.id), {}, { preserveScroll: true, onFinish: cancelStop })
  }

  const facts = [
    run.startedSentence,
    run.actedAs && `acted as ${run.actedAs}`,
    `version ${run.versionNumber}`,
    run.startedAt && `started ${formatWhen(run.startedAt)}`,
    run.finishedAt && `finished ${formatWhen(run.finishedAt)}`,
  ].filter(Boolean).join(", ")

  return (
    <div className="flex flex-col gap-4">
      <Link href={workflowPath(run.workflowId)} className="text-sm text-muted-foreground hover:underline">{run.workflowName}</Link>
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-xl font-semibold">Run of {formatWhen(run.createdAt)}</h1>
            <StatusPill label={runStatusLabel(run.status)} tone={runTone(run.status)} />
            {run.test && <span className="rounded-full border border-border px-2 py-0.5 text-[11px] text-muted-foreground">Test</span>}
            {run.pinned && <span className="rounded-full border border-border px-2 py-0.5 text-[11px] text-muted-foreground">Pinned</span>}
          </div>
          <p className="mt-1 text-sm text-muted-foreground">{facts}.</p>
          {!run.detailsPruned && <p className="mt-1 text-sm text-muted-foreground">It spent {spentWords(run)}.</p>}
        </div>
        {canManage && (
          <div className="flex flex-wrap gap-2">
            <Blocked reason={run.pinned ? undefined : run.pinBlockedReason} side="bottom">
              <Button size="sm" variant="outline" disabled={!run.pinned && Boolean(run.pinBlockedReason)} onClick={pin}>
                {run.pinned ? <IconPinnedOff className="size-4" /> : <IconPin className="size-4" />}
                {run.pinned ? "Unpin" : "Pin"}
              </Button>
            </Blocked>
            <Blocked reason={run.cancelBlockedReason} side="bottom">
              <Button size="sm" variant="outline" disabled={Boolean(run.cancelBlockedReason)} onClick={() => setStopping(true)}>
                <IconPlayerStop className="size-4" />
                Stop run
              </Button>
            </Blocked>
          </div>
        )}
      </div>
      {run.error && (
        <Alert variant="destructive">
          <IconAlertTriangle className="size-4" />
          <AlertDescription>{run.error}</AlertDescription>
        </Alert>
      )}
      <ConfirmDeleteDialog
        open={stopping}
        title="Stop this run?"
        description="Every step still going stops, and nothing after them runs. What already ran stays as it is."
        confirmLabel="Stop run"
        cancelLabel="Keep it running"
        onConfirm={stop}
        onCancel={cancelStop}
      />
    </div>
  )
}
