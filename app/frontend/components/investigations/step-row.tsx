import { IconChevronRight } from "@tabler/icons-react"
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
    : "No gateway receipt"

  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-xs text-muted-foreground/80">{receipt}</span>
      {step.failure && <span className="text-sm text-rose-600 dark:text-rose-400">{step.failure}</span>}
      {step.result && (
        <>
          <button
            type="button"
            onClick={toggle}
            aria-expanded={open}
            className="inline-flex w-fit items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-foreground"
          >
            <IconChevronRight className={`size-3.5 transition-transform ${open ? "rotate-90" : ""}`} />
            {open ? "Hide what it returned" : "Show what it returned"}
          </button>
          {open && (
            <pre className="max-h-96 overflow-auto rounded-md border border-border bg-muted/40 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap">
              {step.result}
            </pre>
          )}
        </>
      )}
    </div>
  )
}
