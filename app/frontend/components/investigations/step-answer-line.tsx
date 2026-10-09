import { IconExternalLink } from "@tabler/icons-react"

import { answerSize, type StepOutcome } from "@/lib/step-outcome"

// How much a step that answered returned, with a link to it at its source when there is one.
export function StepAnswerLine({ outcome }: { outcome: StepOutcome }) {
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
