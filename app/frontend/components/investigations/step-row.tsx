import { IconAlertCircle, IconChevronRight } from "@tabler/icons-react"
import { useState } from "react"

import { formatTime } from "@/lib/formatters"
import { DECISION_LABELS, labelFor } from "@/components/investigations/labels"
import type { InvestigationStep } from "@/types/serializers"

// Under a step, the ledger's receipt, why it failed if it did, and what it returned, folded until asked for.
export function StepDetails({ step }: { step: InvestigationStep }) {
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
      {step.failure && (
        <span className="flex items-start gap-1.5 text-sm text-error">
          <IconAlertCircle className="mt-0.5 size-3.5 shrink-0" />
          {step.failure}
        </span>
      )}
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
