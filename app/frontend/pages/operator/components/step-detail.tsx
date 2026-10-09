import { StepActions } from "@/pages/operator/components/step-actions"
import type { OperatorWorkflow } from "@/types/serializers"

type Step = OperatorWorkflow["steps"][number]

export function StepDetail({ step }: { step: Step }) {
  return (
    <div className="flex flex-col gap-3">
      <p className="text-fg-muted text-[10.5px] font-medium tracking-[0.18em] uppercase">Selected step</p>
      <p className="font-mono text-sm font-medium">{step.name}</p>
      <dl className="grid grid-cols-[90px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm">
        <dt className="text-muted-foreground">Status</dt>
        <dd className="capitalize">{step.status}</dd>
        <dt className="text-muted-foreground">Attempts</dt>
        <dd className="font-mono">{step.attempts} of {step.maxAttempts ?? "-"}</dd>
        <dt className="text-muted-foreground">Took</dt>
        <dd className="font-mono">{step.seconds != null ? `${step.seconds} s` : "-"}</dd>
        <dt className="text-muted-foreground">Waits for</dt>
        <dd className="font-mono text-xs">{step.dependsOn.length > 0 ? step.dependsOn.join(", ") : "nothing"}</dd>
      </dl>
      {step.skipReason && <p className="text-muted-foreground text-sm">{step.skipReason}</p>}
      {step.lastError && (
        <pre className="bg-muted/40 max-h-64 overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap text-error">{step.lastError}</pre>
      )}
      {step.actionBlockedReason === null && <StepActions stepId={step.id} stepName={step.name} />}
    </div>
  )
}
