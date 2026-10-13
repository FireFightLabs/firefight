import { formatWhen, stepStatusLabel, stepTone } from "@/pages/halon/components/workflows/labels"
import { JsonBlock } from "@/pages/halon/components/workflows/json-block"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"
import type { WorkflowRunStep } from "@/pages/halon/components/workflows/types"

const DONE = "succeeded"

function itemWords(iteration: string): string {
  return `Item ${iteration.split(".").map((place) => Number(place) + 1).join(" of item ")}`
}

// One step as it ran: how it stands, what it waited on, why it failed, and what it took in and gave back.
export function RunStepRow({ step }: { step: WorkflowRunStep }) {
  const timing = step.startedAt ? `Started ${formatWhen(step.startedAt)}${step.finishedAt ? `, finished ${formatWhen(step.finishedAt)}` : ""}` : null

  return (
    <li className="flex flex-col gap-2 py-3 first:pt-0 last:pb-0">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium">{step.name}</span>
        <span className="text-xs text-muted-foreground">{step.kindLabel}</span>
        <StatusPill label={stepStatusLabel(step.status)} tone={stepTone(step.status)} />
        {step.simulated && <span className="rounded-full border border-border px-2 py-0.5 text-[11px] text-muted-foreground">Shown, not made</span>}
        {step.real && <span className="rounded-full border border-warning-border bg-warning-tint px-2 py-0.5 text-[11px] text-warning">Made for real in this test</span>}
        {step.route && <span className="text-xs text-muted-foreground">Took the {step.route} route</span>}
        {step.iteration && <span className="text-xs text-muted-foreground">{itemWords(step.iteration)}</span>}
      </div>
      {step.waitingOn && <p className="text-sm text-fg-secondary">{step.waitingOn}</p>}
      {step.error && <p className="break-words text-sm text-destructive">{step.error}</p>}
      {step.undo && step.status === DONE && !step.simulated && <p className="text-xs text-muted-foreground">To undo: {step.undo}</p>}
      <p className="text-xs text-muted-foreground">
        {timing}
        {step.attempts > 1 && ` after ${step.attempts} attempts`}
      </p>
      <div className="flex flex-col gap-1">
        <JsonBlock label="What it took in" value={step.input} />
        <JsonBlock label="What it gave back" value={step.output} />
      </div>
    </li>
  )
}
