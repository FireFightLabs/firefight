import { REMEDIATION_STEP_LABELS } from "@/components/investigations/labels"
import type { InvestigationRemediationPlan, InvestigationRemediationStep } from "@/types/serializers"

// Step numbers read as a list, such as "1, 2 and 3".
function listed(numbers: number[]): string {
  const words = numbers.map(String)
  return words.length < 2 ? words.join("") : `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}`
}

function where(step: InvestigationRemediationStep): string | undefined {
  return step.repository ?? step.action
}

function after(step: InvestigationRemediationStep): string | undefined {
  if (step.dependsOn.length === 0) {
    return undefined
  }
  const steps = listed(step.dependsOn)
  return step.dependsOn.length === 1 ? `After step ${steps}` : `After steps ${steps}`
}

// How to fix what the run found, step by step, with how to undo each and how to tell it worked.
export function FixPlan({ fix }: { fix: InvestigationRemediationPlan }) {
  return (
    <div className="flex flex-col gap-3">
      <p>{fix.summary}</p>
      <ol className="flex flex-col gap-2.5">
        {fix.steps.map((step) => (
          <li key={step.id} className="flex gap-3 rounded-lg border border-border bg-background/50 px-3 py-2.5">
            <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-muted text-[11px] font-semibold tabular-nums">
              {step.position}
            </span>
            <div className="flex min-w-0 flex-col gap-1">
              <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-muted-foreground">
                <span className="font-medium uppercase tracking-wider">{REMEDIATION_STEP_LABELS[step.kind]}</span>
                {where(step) && <code className="truncate font-mono">{where(step)}</code>}
                {after(step) && <span>{after(step)}</span>}
              </span>
              <span>{step.description}</span>
              {step.missing && <span className="text-xs text-amber-700 dark:text-amber-400">Needs: {step.missing}</span>}
              {step.undo && <span className="text-xs text-muted-foreground">To undo: {step.undo}</span>}
            </div>
          </li>
        ))}
      </ol>
      {fix.verify && <p className="text-xs text-muted-foreground">How to tell it worked: {fix.verify}</p>}
    </div>
  )
}
