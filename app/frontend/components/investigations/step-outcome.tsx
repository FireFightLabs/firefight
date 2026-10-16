import { IconExternalLink } from "@tabler/icons-react"

import type { InvestigationRemediationStep } from "@/types/serializers"

// What a step that went through produced, its link visible, or why it was already done.
export function StepOutcome({ step }: { step: InvestigationRemediationStep }) {
  if (step.alreadyDoneLine) {
    return <span className="text-xs text-fg-body">{step.alreadyDoneLine}</span>
  }
  if (!step.outcome) {
    return null
  }

  return (
    <span className="text-xs text-fg-body">
      {step.outcome.lead}:{" "}
      <a href={step.outcome.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 font-medium text-fg-primary hover:underline">
        {step.outcome.label}
        <IconExternalLink className="size-3.5 text-fg-muted" />
      </a>
    </span>
  )
}
