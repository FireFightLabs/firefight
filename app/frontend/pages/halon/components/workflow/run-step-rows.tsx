import { WORKFLOW_STEP_GROUP } from "@/lib/generated/constants"
import { cn } from "@/lib/utils"
import { StepIcon } from "@/pages/halon/components/workflow/step-icon"
import { durationLabel, STEP_GOING, STEP_STATUS_LABELS, STEP_STATUS_TONES } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunDetail, WorkflowRunStep, WorkflowStepNode } from "@/types/serializers"

interface RunStepRowsProps {
  run: WorkflowRunDetail
  steps: WorkflowStepNode[]
  // The time now, ticking while the run goes, for how long a step still going has taken.
  now: number
  onPick: (stepId: string) => void
}

interface Reached {
  step: WorkflowStepNode
  rows: WorkflowRunStep[]
  // The row the line speaks for: an item still going, else the last one.
  row: WorkflowRunStep
  line: string | null
}

// The steps a run reached in the order they started, one line each: its state and time, and what it is doing now while it
// goes or the last thing it did once it ended. Picking one opens its whole log.
export function RunStepRows({ run, steps, now, onPick }: RunStepRowsProps) {
  const reached = reachedSteps(run, steps)

  if (reached.length === 0) {
    return <p className="text-xs text-fg-muted">No step has started yet.</p>
  }

  return (
    <ol className="divide-y divide-border rounded-sm border border-border">
      {reached.map(({ step, rows, row, line }) => (
        <li key={step.id}>
          <button type="button" onClick={() => onPick(step.id)} className="flex w-full items-start gap-2 px-2.5 py-2 text-left hover:bg-surface-hover">
            <StepIcon icon={step.icon} halon={step.group === WORKFLOW_STEP_GROUP.HALON} size="sm" />
            <span className="min-w-0 flex-1 space-y-0.5">
              <span className="flex items-baseline justify-between gap-2">
                <span className="truncate text-xs font-medium text-fg-primary">{step.title}</span>
                <span className={cn("shrink-0 text-[11px]", STEP_STATUS_TONES[row.status])}>
                  {rows.length > 1 ? `${rows.length} items · ` : ""}
                  {STEP_STATUS_LABELS[row.status]}
                  {row.startedAt && ` · ${durationLabel(row.startedAt, row.finishedAt, now)}`}
                </span>
              </span>
              {line && <span className="line-clamp-2 block text-[11.5px] text-fg-secondary [overflow-wrap:anywhere]">{line}</span>}
            </span>
          </button>
        </li>
      ))}
    </ol>
  )
}

// Each step with the rows it ran, in the order it first started. A step that never started is left to the canvas.
function reachedSteps(run: WorkflowRunDetail, steps: WorkflowStepNode[]): Reached[] {
  const started = run.steps.filter((row) => row.startedAt)
  const firstStart = (rows: WorkflowRunStep[]) => Math.min(...rows.map((row) => new Date(row.startedAt ?? 0).getTime()))
  return steps
    .map((step) => ({ step, rows: started.filter((row) => row.stepKey === step.id) }))
    .filter((each) => each.rows.length > 0)
    .sort((left, right) => firstStart(left.rows) - firstStart(right.rows))
    .map(({ step, rows }) => {
      const row = rows.find((each) => STEP_GOING.includes(each.status)) ?? latestFinished(rows)
      return { step, rows, row, line: row.now ?? row.log[row.log.length - 1]?.text ?? null }
    })
}

// The item that finished last, the last to start among items with the same end, so the line is the newest whatever
// order the rows arrived in.
function latestFinished(rows: WorkflowRunStep[]): WorkflowRunStep {
  const moment = (value: string | null | undefined) => (value ? new Date(value).getTime() : 0)
  return rows.reduce((latest, row) => {
    const later = moment(row.finishedAt) - moment(latest.finishedAt) || moment(row.startedAt) - moment(latest.startedAt) || row.iteration.localeCompare(latest.iteration)
    return later > 0 ? row : latest
  })
}
