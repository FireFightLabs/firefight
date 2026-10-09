import { IconChevronRight } from "@tabler/icons-react"
import { useState } from "react"

import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { receiptLine } from "@/components/investigations/labels"
import { StepAnswerLine } from "@/components/investigations/step-answer-line"
import { StepFailureLine } from "@/components/investigations/step-failure-line"
import type { InvestigationStep } from "@/types/serializers"

// Under a step, the ledger's receipt, how it went in the provider's own words, and what it returned, folded until
// asked for.
export function StepDetails({ step }: { step: InvestigationStep }) {
  const outcome = step.outcome
  const [open, setOpen] = useState(false)

  function toggle() {
    setOpen(!open)
  }

  const receipt = step.receipt ? receiptLine(step.receipt) : "Allowed. Reads of Firefight's own records are not logged"

  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs text-fg-muted">{receipt}</span>
      {outcome && outcome.kind !== STEP_OUTCOME_KINDS.ANSWERED && <StepFailureLine outcome={outcome} fallback={step.failure} />}
      {outcome?.kind === STEP_OUTCOME_KINDS.ANSWERED && <StepAnswerLine outcome={outcome} />}
      {step.result && (
        <>
          <button
            type="button"
            onClick={toggle}
            aria-expanded={open}
            className="inline-flex w-fit items-center gap-1 rounded-sm text-xs text-fg-secondary transition-colors duration-150 hover:text-fg-primary"
          >
            <IconChevronRight className={`size-3.5 transition-transform duration-150 motion-reduce:transition-none ${open ? "rotate-90" : ""}`} />
            {open ? "Hide what it returned" : "Show what it returned"}
          </button>
          {open && (
            <pre className="max-h-96 overflow-auto rounded-md border border-border bg-surface-code p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap text-fg-body">
              {step.result}
            </pre>
          )}
        </>
      )}
    </div>
  )
}
