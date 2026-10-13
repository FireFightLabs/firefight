import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import type { WorkflowDetail } from "@/types/serializers"

// Each step in the order it runs, with whether it only reads or changes something, and how a change is put back.
export function StepsCard({ workflow }: { workflow: WorkflowDetail }) {
  const version = workflow.showsDraft ? `the draft, version ${workflow.draftNumber}` : `version ${workflow.liveNumber}`

  return (
    <Card>
      <CardHeader>
        <CardTitle>Steps</CardTitle>
        <CardDescription className="mt-1">As in {version}, in the order they run.</CardDescription>
      </CardHeader>
      <CardContent>
        {workflow.steps.length === 0 ? (
          <p className="text-sm text-muted-foreground">It has no steps yet.</p>
        ) : (
          <ol className="flex flex-col divide-y">
            {workflow.steps.map((step, index) => (
              <li key={step.id} className="flex gap-3 py-3 first:pt-0 last:pb-0">
                <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-medium tabular-nums">{index + 1}</span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{step.name}</span>
                    <span className="text-xs text-muted-foreground">{step.kindLabel}</span>
                    <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${step.changes ? "border-warning-border bg-warning-tint text-warning" : "border-border text-muted-foreground"}`}>
                      {step.changes ? "Changes" : "Reads"}
                    </span>
                  </div>
                  {step.summary && <p className="mt-1 break-words text-sm text-fg-secondary">{step.summary}</p>}
                  {step.undo && <p className="mt-1 text-xs text-muted-foreground">To undo: {step.undo}</p>}
                </div>
              </li>
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  )
}
