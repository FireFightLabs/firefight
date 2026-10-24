import { router } from "@inertiajs/react"
import { IconArrowBackUp, IconArrowLeft, IconPin, IconPlayerPlay, IconPlayerSkipForward, IconRefresh } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { dollarsFromMicros, secondsInWords } from "@/lib/formatters"
import { cn } from "@/lib/utils"
import { WORKFLOW_STEP_EFFECT, WORKFLOW_STEP_GROUP } from "@/lib/generated/constants"
import { workflowPinsPath, workflowRunRerunPath, workflowRunStepRetryPath, workflowRunStepSkipPath } from "@/lib/routes"
import { AskPanel } from "@/pages/halon/components/workflow/ask-panel"
import { JsonBlock } from "@/pages/halon/components/workflow/json-block"
import { SavedResultDialog } from "@/pages/halon/components/workflow/saved-result-dialog"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { StepLog } from "@/pages/halon/components/workflow/step-log"
import { WatchActivity } from "@/pages/halon/components/workflow/watch-activity"
import { CANVAS_VISIT, RUN_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import { routeLabel } from "@/pages/halon/lib/workflow/labels"
import { durationLabel, STEP_GOING, STEP_STATUS_LABELS, STEP_STATUS_TONES } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunDetail, WorkflowRunStep, WorkflowStepNode } from "@/types/serializers"
import { useNow } from "@/pages/halon/hooks/use-now"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"

interface RunStepPanelProps {
  workflowId: string
  run: WorkflowRunDetail
  step: WorkflowStepNode
  // There is a draft whose step this output can be pinned on.
  canPin: boolean
  // Goes back to the run as a whole.
  onBack: () => void
}

// What one step did in the run shown: its state and time, what it is doing now while it goes, where a watch it keeps
// stands, its log of everything it did (every call it made through the gateway, each tool Halon called for it, what a
// watch said and saw), what it was given and gave, the results it kept and its error, with Try again, Skip, Start again
// from here and Pin this output. A step inside a for each lists each item it ran.
export function RunStepPanel({ workflowId, run, step, canPin, onBack }: RunStepPanelProps) {
  const canEdit = useWorkflowAccess().build
  const rows = run.steps.filter((row) => row.stepKey === step.id)
  const [ chosen, setChosen ] = useState(0)
  const [ opened, setOpened ] = useState<{ id: string; handle: string } | null>(null)
  const row: WorkflowRunStep | undefined = rows[Math.min(chosen, rows.length - 1)]
  const going = row !== undefined && STEP_GOING.includes(row.status)
  const now = useNow(going)

  function retry() {
    if (row) {
      router.post(workflowRunStepRetryPath(workflowId, run.id, row.stepKey), { iteration: row.iteration }, RUN_VISIT)
    }
  }

  function skip() {
    if (row) {
      router.post(workflowRunStepSkipPath(workflowId, run.id, row.stepKey), { iteration: row.iteration }, RUN_VISIT)
    }
  }

  function rerun() {
    router.post(workflowRunRerunPath(workflowId, run.id), { step_key: step.id }, { preserveScroll: true })
  }

  function pin() {
    router.post(workflowPinsPath(workflowId), { step_id: step.id, run_id: run.id }, CANVAS_VISIT)
  }

  function closeResult() {
    setOpened(null)
  }

  function chooseItem(index: number) {
    return () => setChosen(index)
  }

  function openResult(result: { id: string; handle: string }) {
    return () => setOpened(result)
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="border-b border-border px-1.5 py-1">
        <Button type="button" variant="ghost" size="sm" className="h-7 px-1.5 text-xs text-fg-secondary" onClick={onBack}>
          <IconArrowLeft className="size-3.5" />
          The whole run
        </Button>
      </div>
      <header className="flex items-start gap-2.5 border-b border-border p-3">
        <StepIcon icon={step.icon} halon={step.group === WORKFLOW_STEP_GROUP.HALON} />
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm leading-tight font-semibold text-fg-headline">{step.title}</h3>
          <p className="mt-0.5 text-xs text-fg-muted">{step.kindLabel}</p>
          {row && (
            <p className={cn("mt-1.5 text-xs", STEP_STATUS_TONES[row.status])}>
              {STEP_STATUS_LABELS[row.status]}
              {row.startedAt && ` · ${durationLabel(row.startedAt, row.finishedAt, now)}`}
              {row.attempts > 1 && ` · ${row.attempts} tries`}
              {row.route && ` · took ${routeLabel(row.route, step.routeLabels)}`}
            </p>
          )}
          {row?.now && <p className="mt-1 text-xs text-fg-primary [overflow-wrap:anywhere]" aria-live="polite">{row.now}</p>}
        </div>
      </header>
      <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-3">
        {!row && <p className="text-xs text-fg-muted">The run did not reach this step.</p>}
        {rows.length > 1 && (
          <div className="flex flex-wrap gap-1" role="group" aria-label="Items">
            {rows.map((each, index) => (
              <button
                key={each.id}
                type="button"
                aria-pressed={index === chosen}
                onClick={chooseItem(index)}
                className={cn("rounded-sm border px-2 py-0.5 font-mono text-[11px]", index === chosen ? "border-brand text-brand" : "border-border text-fg-muted", STEP_STATUS_TONES[each.status])}
              >
                Item {each.iteration.split(".").map((part) => Number(part) + 1).join(".")}
              </button>
            ))}
          </div>
        )}
        {row && (
          <>
            {row.stoodIn && (
              <p className="rounded-sm border border-brand-border bg-brand-tint px-2.5 py-2 text-xs text-brand">
                {run.rerunOfId ? "It did not run. What it gave in the run this one started from stood in for it." : "It did not run. Its pinned output stood in for it."}
              </p>
            )}
            {row.simulated && step.effect === WORKFLOW_STEP_EFFECT.CHANGES && (
              <p className="rounded-sm border border-border-strong px-2.5 py-2 text-xs text-fg-secondary">Shown, not made. A test run makes only the changes the tester turned on, and this one was not.</p>
            )}
            {row.waitingApproval && (
              <p className="rounded-sm border border-warning-border bg-warning-tint px-2.5 py-2 text-xs text-warning">It waits for an approver to allow what it called.</p>
            )}
            {row.ask && <AskPanel workflowId={workflowId} runId={run.id} ask={row.ask} />}
            {row.error && <p className="rounded-sm border border-error-border bg-error-tint px-2.5 py-2 text-xs text-error [overflow-wrap:anywhere]">{row.error}</p>}
            {row.note && <p className="rounded-sm border border-brand-border bg-brand-tint px-2.5 py-2 text-xs text-brand [overflow-wrap:anywhere]">{row.note}</p>}
            {row.watch && <WatchActivity watch={row.watch} now={now} />}
            <StepLog entries={row.log} going={going} />
            {row.sandboxSeconds > 0 && (
              <p className="text-xs text-fg-muted">Used the sandbox for {secondsInWords(row.sandboxSeconds)}, which cost {dollarsFromMicros(row.sandboxMicros)}.</p>
            )}
            <JsonBlock label="What it was given" value={row.input} />
            <JsonBlock label="What it gave" value={row.output} />
            {row.savedResults.length > 0 && (
              <section className="space-y-1">
                <h5 className="text-[11px] font-medium text-fg-secondary">Kept whole</h5>
                {row.savedResults.map((result) => (
                  <Button key={result.id} type="button" variant="outline" size="sm" className="h-7 text-xs" onClick={openResult(result)}>
                    {result.handle}
                    {result.bytes ? ` · ${Math.ceil(result.bytes / 1024)} KB` : ""}
                  </Button>
                ))}
              </section>
            )}
            {row.screenshots.length > 0 && (
              <section className="space-y-1.5">
                <h5 className="text-[11px] font-medium text-fg-secondary">What the browser saw</h5>
                {row.screenshots.map((shot) => (
                  <figure key={shot.id} className="space-y-1">
                    <a href={shot.url} target="_blank" rel="noreferrer">
                      <img src={shot.url} alt={shot.caption} className="w-full rounded-sm border border-border" />
                    </a>
                    <figcaption className="text-[11px] text-fg-muted">{shot.caption}</figcaption>
                  </figure>
                ))}
              </section>
            )}
          </>
        )}
      </div>
      {canEdit && (
        <footer className="flex flex-wrap items-center gap-2 border-t border-border p-3">
          {row && (
            <Blocked reason={row.retryBlockedReason ?? undefined} side="top">
              <Button type="button" variant="outline" size="sm" disabled={row.retryBlockedReason != null} onClick={retry}>
                <IconRefresh className="size-4" />
                Try again
              </Button>
            </Blocked>
          )}
          {row && (
            <Blocked reason={row.skipBlockedReason ?? undefined} side="top">
              <Button type="button" variant="outline" size="sm" disabled={row.skipBlockedReason != null} onClick={skip}>
                <IconPlayerSkipForward className="size-4" />
                Skip
              </Button>
            </Blocked>
          )}
          {row && (
            <Blocked reason={row.rerunBlockedReason ?? undefined} side="top">
              <Button type="button" variant="outline" size="sm" disabled={row.rerunBlockedReason != null} onClick={rerun}>
                {run.test ? <IconPlayerPlay className="size-4" /> : <IconArrowBackUp className="size-4" />}
                Start again from here
              </Button>
            </Blocked>
          )}
          {canPin && row?.output && (
            <Button type="button" variant="outline" size="sm" onClick={pin}>
              <IconPin className="size-4" />
              Pin this output
            </Button>
          )}
        </footer>
      )}
      <SavedResultDialog workflowId={workflowId} runId={run.id} result={opened} onClose={closeResult} />
    </div>
  )
}
