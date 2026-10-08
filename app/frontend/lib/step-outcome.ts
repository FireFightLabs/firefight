import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import type { InvestigationStep } from "@/types/serializers"

// What a step got back, the same shape for a chat's steps and a run's (Chat::StepOutcome on the server).
export type StepOutcome = NonNullable<InvestigationStep["outcome"]>

export type StepOutcomeKind = (typeof STEP_OUTCOME_KINDS)[keyof typeof STEP_OUTCOME_KINDS]

export const OUTCOME_LABELS: Record<StepOutcomeKind, string> = {
  [STEP_OUTCOME_KINDS.ANSWERED]: "Returned",
  [STEP_OUTCOME_KINDS.FAILED]: "Failed",
  [STEP_OUTCOME_KINDS.NOT_FOUND]: "Not found",
  [STEP_OUTCOME_KINDS.REFUSED]: "Refused",
}

const COUNT = new Intl.NumberFormat("en-US")

function counted(count: number, one: string, many: string): string {
  return `${COUNT.format(count)} ${count === 1 ? one : many}`
}

export function isOutcomeKind(value: string): value is StepOutcomeKind {
  return Object.values<string>(STEP_OUTCOME_KINDS).includes(value)
}

export function outcomeLabel(outcome: StepOutcome): string {
  return isOutcomeKind(outcome.kind) ? OUTCOME_LABELS[outcome.kind] : OUTCOME_LABELS[STEP_OUTCOME_KINDS.FAILED]
}

// How long an answer was, such as "12 lines, 3,201 characters", or that it was empty.
export function answerSize(outcome: StepOutcome): string {
  if (outcome.size === 0) {
    return "Returned nothing"
  }

  return `Returned ${counted(outcome.total, "line", "lines")}, ${counted(outcome.size, "character", "characters")}`
}
