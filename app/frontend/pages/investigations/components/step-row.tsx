import { IconChevronRight } from "@tabler/icons-react"
import { useState } from "react"

import { Badge } from "@/components/ui/badge"
import { formatTime } from "@/lib/formatters"
import { formatSeconds } from "@/pages/investigations/lib/format"
import { DECISION_LABELS, STEP_LABELS, labelFor } from "@/pages/investigations/lib/labels"
import type { InvestigationStep } from "@/types/serializers"

// One tool call with how it went and the ledger's receipt. What it returned stays folded until asked for.
export function StepRow({ step }: { step: InvestigationStep }) {
  const [open, setOpen] = useState(false)

  function toggle() {
    setOpen(!open)
  }

  const receipt = step.receipt
    ? `${labelFor(DECISION_LABELS, step.receipt.decision)} by the gateway at ${formatTime(step.receipt.at)}`
    : "No gateway receipt"

  return (
    <li id={`step-${step.position}`} className="flex scroll-mt-20 flex-col gap-1.5 py-3 first:pt-0 last:pb-0">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-muted-foreground w-6 shrink-0 text-right text-sm tabular-nums">{step.position}</span>
        <span className="font-medium">{step.label}</span>
        <Badge variant="outline">{labelFor(STEP_LABELS, step.status)}</Badge>
        <span className="text-muted-foreground text-xs">{formatSeconds(step.seconds)}</span>
      </div>
      <div className="flex flex-col gap-1.5 pl-9">
        <span className="text-muted-foreground text-xs">{receipt}</span>
        {step.failure && <span className="text-destructive text-sm">{step.failure}</span>}
        {step.result && (
          <>
            <button
              type="button"
              onClick={toggle}
              aria-expanded={open}
              className="text-muted-foreground inline-flex w-fit items-center gap-1 text-xs transition-colors hover:text-foreground"
            >
              <IconChevronRight className={`size-3.5 transition-transform ${open ? "rotate-90" : ""}`} />
              {open ? "Hide what it returned" : "Show what it returned"}
            </button>
            {open && (
              <pre className="bg-muted max-h-96 overflow-auto rounded-md p-3 text-xs whitespace-pre-wrap">{step.result}</pre>
            )}
          </>
        )}
      </div>
    </li>
  )
}
