import { IconAlertCircle, IconCircleMinus } from "@tabler/icons-react"

import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { outcomeLabel, type StepOutcome } from "@/lib/step-outcome"

// A failure is the provider's own words in red. A not found answered the check, so it reads as quietly as an answer.
export function StepFailureLine({ outcome, fallback }: { outcome: StepOutcome; fallback?: string }) {
  const failed = outcome.kind === STEP_OUTCOME_KINDS.FAILED
  const Mark = failed ? IconAlertCircle : IconCircleMinus
  return (
    <span className={`flex items-start gap-1.5 text-sm ${failed ? "text-error" : "text-fg-secondary"}`}>
      <Mark className="mt-0.5 size-3.5 shrink-0" />
      <span>
        <span className="font-medium">{outcomeLabel(outcome)}</span>
        {(outcome.said ?? fallback) && <span className={failed ? "" : "text-fg-muted"}>. {outcome.said ?? fallback}</span>}
      </span>
    </span>
  )
}
