import { router } from "@inertiajs/react"
import { IconPlayerStop } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { cn } from "@/lib/utils"
import { dollars, dollarsFromMicros, formatDateTime } from "@/lib/formatters"
import { cancelWorkflowRunPath, pinWorkflowRunPath, unpinWorkflowRunPath } from "@/lib/routes"
import { JsonBlock } from "@/pages/halon/components/workflow/json-block"
import { RunStepRows } from "@/pages/halon/components/workflow/run-step-rows"
import { useNow } from "@/pages/halon/hooks/use-now"
import { WhatStartedIt } from "@/pages/halon/components/workflow/what-started-it"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"
import { RUN_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import { durationLabel, RUN_STATUS_LABELS, RUN_STATUS_TONES, STEP_GOING, untilLabel } from "@/pages/halon/lib/workflow/run-states"
import { WORKFLOW_RUN_OPEN_STATUSES, WORKFLOW_RUN_STATUS } from "@/lib/generated/constants"
import type { WorkflowRunDetail, WorkflowStepNode } from "@/types/serializers"

const OPEN_RUN: readonly string[] = WORKFLOW_RUN_OPEN_STATUSES

interface RunSummaryProps {
  workflowId: string
  run: WorkflowRunDetail
  steps: WorkflowStepNode[]
  // Opens a step's whole log.
  onPick: (stepId: string) => void
}

interface NowLine {
  key: string
  text: string
}

// The run shown, when no step is picked: how it stands, what each step still going is doing right now, every step it
// reached with its state and latest line (each opening its whole log), who started it and with what, what it handed back
// and the error that stopped it, with Stop for a run still going and Pin, which keeps its details past the workspace's
// run history.
export function RunSummary({ workflowId, run, steps, onPick }: RunSummaryProps) {
  const canManage = useWorkflowAccess().manage
  const going = OPEN_RUN.includes(run.status)
  const now = useNow(going)
  const happening = going ? nowLines(run, steps, now) : []
  const [ cancelling, setCancelling ] = useState(false)

  function askCancel() {
    setCancelling(true)
  }

  function keepCancelling() {
    setCancelling(false)
  }

  function cancel() {
    setCancelling(false)
    router.post(cancelWorkflowRunPath(workflowId, run.id), {}, RUN_VISIT)
  }

  function pin(checked: boolean) {
    router.patch(checked ? pinWorkflowRunPath(workflowId, run.id) : unpinWorkflowRunPath(workflowId, run.id), {}, RUN_VISIT)
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="space-y-1.5 border-b border-border p-3">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold text-fg-headline">{run.test ? "Test run" : "Run"} of version {run.versionNumber}</h3>
          <span className={cn("rounded-full border px-2 py-px text-[11px] font-medium", RUN_STATUS_TONES[run.status])}>{RUN_STATUS_LABELS[run.status]}</span>
        </div>
        <p className="text-xs text-fg-muted">
          {run.startedSentence} · {formatDateTime(run.createdAt)}
          {run.startedAt && ` · ${durationLabel(run.startedAt, run.finishedAt, now)}`}
        </p>
      </header>
      <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-3">
        {going && (
          <section className="space-y-1 rounded-sm border border-warning-border bg-warning-tint px-2.5 py-2" aria-label="Now" aria-live="polite">
            <h5 className="text-[11px] font-medium text-warning">Now</h5>
            {happening.map((line) => (
              <p key={line.key} className="text-xs text-fg-primary [overflow-wrap:anywhere]">{line.text}</p>
            ))}
          </section>
        )}
        {!run.detailsPruned && (
          <section className="space-y-1" aria-label="Steps">
            <h5 className="text-[11px] font-medium text-fg-secondary">Steps</h5>
            <RunStepRows run={run} steps={steps} now={now} onPick={onPick} />
            <p className="text-[11px] text-fg-muted">Pick a step here or on the canvas for everything it did.</p>
          </section>
        )}
        {run.detailsPruned && <p className="text-xs text-fg-muted">This run&apos;s details went with the workspace&apos;s run history. Its one line stays.</p>}
        {run.error && <p className="rounded-sm border border-error-border bg-error-tint px-2.5 py-2 text-xs text-error [overflow-wrap:anywhere]">{run.error}</p>}
        {run.notes.length > 0 && (
          <section className="space-y-1">
            <h5 className="text-[11px] font-medium text-fg-secondary">Skipped</h5>
            {run.notes.map((note) => (
              <p key={note} className="rounded-sm border border-brand-border bg-brand-tint px-2.5 py-2 text-xs text-brand [overflow-wrap:anywhere]">{note}</p>
            ))}
          </section>
        )}
        <section className="space-y-1" aria-label="What it spent">
          <h5 className="text-[11px] font-medium text-fg-secondary">What it spent</h5>
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
            <dt className="text-fg-muted">AI</dt>
            <dd className="text-fg-secondary">{dollarsFromMicros(run.aiSpentMicros)}</dd>
            <dt className="text-fg-muted">Sandbox</dt>
            <dd className="text-fg-secondary">{dollarsFromMicros(run.sandboxSpentMicros)}</dd>
            <dt className="text-fg-muted">Ceiling</dt>
            <dd className="text-fg-secondary">{run.costCapCents ? dollars(run.costCapCents) : "None"}</dd>
          </dl>
        </section>
        <WhatStartedIt run={run} />
        <JsonBlock label="What it handed back" value={run.outputs} />
        {canManage && !run.detailsPruned && (
          <div className="flex items-start justify-between gap-3 rounded-sm border border-border p-2.5">
            <div className="space-y-0.5">
              <Label htmlFor="pin-run" className="text-xs">Pin</Label>
              <p className="text-[11.5px] text-fg-muted">A pinned run keeps its details for good. Otherwise they go with the workspace&apos;s run history, and its one line stays.</p>
            </div>
            <Switch id="pin-run" checked={run.pinned} onCheckedChange={pin} />
          </div>
        )}
      </div>
      {canManage && (
        <footer className="flex items-center gap-2 border-t border-border p-3">
          <Blocked reason={run.cancelBlockedReason ?? undefined} side="top">
            <Button type="button" variant="outline" size="sm" disabled={run.cancelBlockedReason != null} onClick={askCancel}>
              <IconPlayerStop className="size-4" />
              Stop run
            </Button>
          </Blocked>
        </footer>
      )}
      <ConfirmDeleteDialog
        open={cancelling}
        title="Stop this run?"
        description="It stops where it is, and so does every run it started. Steps that already ran stay as they ran."
        confirmLabel="Stop run"
        cancelLabel="Keep it running"
        onConfirm={cancel}
        onCancel={keepCancelling}
      />
    </div>
  )
}

// What the run is doing this moment: each step still going with what it is doing and when a watch reads next, or why
// nothing is moving yet.
function nowLines(run: WorkflowRunDetail, steps: WorkflowStepNode[], now: number): NowLine[] {
  const lines = run.steps.filter((row) => STEP_GOING.includes(row.status)).map((row) => {
    const title = steps.find((step) => step.id === row.stepKey)?.title ?? row.stepKey
    const next = row.watch?.active && row.watch.nextCheckAt ? ` It reads next ${untilLabel(row.watch.nextCheckAt, now)}.` : ""
    return { key: row.id, text: `${title}: ${row.now ?? "Working on it."}${next}` }
  })
  if (lines.length > 0) {
    return lines
  }
  if (run.status === WORKFLOW_RUN_STATUS.QUEUED) {
    return [ { key: WORKFLOW_RUN_STATUS.QUEUED, text: "Waiting for a worker to start it." } ]
  }
  if (run.status === WORKFLOW_RUN_STATUS.PAUSED) {
    return [ { key: WORKFLOW_RUN_STATUS.PAUSED, text: "Paused. It carries on once it is resumed." } ]
  }
  return [ { key: "between", text: "Moving on to the next step." } ]
}
