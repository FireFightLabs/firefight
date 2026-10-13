import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { answerSize, outcomeLabel, type StepOutcome } from "@/lib/step-outcome"

// Under an opened step, what came back. A failure and a not found are the provider's own words, and an answer is how it
// starts, how long it is and the page it came from.
export function StepOutcomeDetails({ outcome }: { outcome: StepOutcome }) {
  if (outcome.kind !== STEP_OUTCOME_KINDS.ANSWERED) {
    const failed = outcome.kind === STEP_OUTCOME_KINDS.FAILED
    return (
      <p className="m-0 text-[12px] leading-5">
        <span className={failed ? "font-medium text-red" : "font-medium text-ink-2"}>{outcomeLabel(outcome)}</span>
        {outcome.said && <span className="text-ink-3">. {outcome.said}</span>}
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-1">
      <span className="text-[12px] leading-5 text-ink-2">{answerSize(outcome)}</span>
      {outcome.lines.length > 0 && (
        <pre className="m-0 max-w-full overflow-hidden font-mono text-[11.5px] leading-5 whitespace-pre-wrap text-ink-3 [overflow-wrap:anywhere]">
          {outcome.lines.join("\n")}
        </pre>
      )}
      {outcome.link && (
        <a
          href={outcome.link.url}
          target="_blank"
          rel="noopener noreferrer"
          className="w-fit text-[12px] leading-5 text-ink-2 underline decoration-line-strong underline-offset-2 transition-colors duration-150 hover:text-ink"
        >
          Open in {outcome.link.provider}
        </a>
      )}
    </div>
  )
}
