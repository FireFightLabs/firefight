import { IconChevronRight } from "@tabler/icons-react"

import { cn } from "@/lib/utils"
import { formatDateTime } from "@/lib/formatters"
import { durationLabel, RUN_STATUS_LABELS, RUN_STATUS_TONES } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunRow } from "@/types/serializers"

interface RunsViewProps {
  runs: WorkflowRunRow[]
  onOpen: (runId: string) => void
}

// Every run of the workflow, newest first, test runs among them, each opening on the canvas with what every step did.
export function RunsView({ runs, onOpen }: RunsViewProps) {
  function open(runId: string) {
    return () => onOpen(runId)
  }

  return (
    <div className="h-full overflow-y-auto px-4 py-5">
      <div className="mx-auto max-w-3xl space-y-3">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <h2 className="text-base font-semibold text-fg-headline">Runs</h2>
          <p className="text-[12.5px] text-fg-muted">Each run opens on the canvas with what every step took in, gave back and called.</p>
        </div>
        {runs.length === 0 ? (
          <p className="border border-border bg-surface-card px-4 py-6 text-center text-sm text-fg-muted">No runs yet. Try the draft with Test run to see one here.</p>
        ) : (
          <ol className="space-y-2">
            {runs.map((run) => (
              <li key={run.id}>
                <button type="button" onClick={open(run.id)} className="flex w-full items-start gap-3 border border-border bg-surface-card px-3.5 py-3 text-left hover:border-border-strong">
                  <span className={cn("mt-0.5 rounded-full border px-2 py-px font-mono text-[10.5px]", RUN_STATUS_TONES[run.status])}>{RUN_STATUS_LABELS[run.status]}</span>
                  <span className="min-w-0 flex-1">
                    <span className="flex flex-wrap items-center gap-2 text-[13px] font-medium text-fg-headline">
                      {run.test ? "Test run" : "Run"} of version {run.versionNumber}
                      {run.rerunFromStepKey && <span className="text-xs font-normal text-fg-muted">started again from a step</span>}
                    </span>
                    <span className="mt-0.5 block text-[12px] text-fg-secondary">
                      {run.startedByWords} · {formatDateTime(run.createdAt)}
                      {run.startedAt && ` · ${durationLabel(run.startedAt, run.finishedAt)}`}
                    </span>
                    {run.error && <span className="mt-1 block truncate text-xs text-error">{run.error}</span>}
                  </span>
                  <IconChevronRight className="mt-1 size-4 shrink-0 text-fg-muted" />
                </button>
              </li>
            ))}
          </ol>
        )}
      </div>
    </div>
  )
}
