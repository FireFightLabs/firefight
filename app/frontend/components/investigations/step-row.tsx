import { IconAlertCircle, IconChevronRight, IconCircleMinus, IconExternalLink } from "@tabler/icons-react"
import { useState } from "react"

import { formatTime } from "@/lib/formatters"
import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { answerSize, outcomeLabel, type StepOutcome } from "@/lib/step-outcome"
import { DECISION_LABELS, labelFor } from "@/components/investigations/labels"
import type { InvestigationStep } from "@/types/serializers"

// A failure is the provider's own words in red. A not found answered the check, so it reads as quietly as an answer.
function FailureLine({ outcome, fallback }: { outcome: StepOutcome; fallback?: string }) {
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

function AnswerLine({ outcome }: { outcome: StepOutcome }) {
  return (
    <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-fg-muted">
      <span>{answerSize(outcome)}</span>
      {outcome.link && (
        <a
          href={outcome.link.url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-fg-secondary transition-colors duration-150 hover:text-fg-primary"
        >
          Open in {outcome.link.provider}
          <IconExternalLink className="size-3" />
        </a>
      )}
    </span>
  )
}

// Under a step, the ledger's receipt, how it went in the provider's own words, and what it returned, folded until
// asked for.
export function StepDetails({ step }: { step: InvestigationStep }) {
  const outcome = step.outcome
  const [open, setOpen] = useState(false)

  function toggle() {
    setOpen(!open)
  }

  const receipt = step.receipt
    ? `${labelFor(DECISION_LABELS, step.receipt.decision)} by the gateway at ${formatTime(step.receipt.at)}`
    : "Allowed. Reads of Firefight's own records are not logged"

  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs text-fg-muted">{receipt}</span>
      {outcome && outcome.kind !== STEP_OUTCOME_KINDS.ANSWERED && <FailureLine outcome={outcome} fallback={step.failure} />}
      {outcome?.kind === STEP_OUTCOME_KINDS.ANSWERED && <AnswerLine outcome={outcome} />}
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
