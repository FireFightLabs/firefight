import { JsonBlock } from "@/pages/halon/components/workflow/json-block"
import type { WorkflowRunDetail } from "@/types/serializers"

// The inputs a run was given and what started it. A run started by hand says who started it, then what they gave it,
// and anything sent along with it, such as the runbook it was run from.
export function WhatStartedIt({ run }: { run: WorkflowRunDetail }) {
  if (!run.startedByHand) {
    return (
      <>
        <JsonBlock label="Inputs" value={run.inputs} />
        <JsonBlock label="What started it" value={run.triggerPayload} />
      </>
    )
  }

  const sentAlong = Object.keys(run.triggerPayload).length > 0

  return (
    <>
      <section className="space-y-1" aria-label="What started it">
        <h5 className="text-[11px] font-medium text-fg-secondary">What started it</h5>
        <p className="text-xs text-fg-primary">{run.startedByHand}</p>
      </section>
      <JsonBlock label="Inputs given" value={run.inputs} />
      {sentAlong && <JsonBlock label="Sent along with it" value={run.triggerPayload} />}
    </>
  )
}
