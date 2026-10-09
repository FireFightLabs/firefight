import { OPERATOR_REGRESSION_CASE_STATUSES, OPERATOR_REGRESSION_TRIGGERS } from "@/pages/operator/generated/constants"
import { TONE_CLASSES, type Tone } from "@/pages/operator/lib/tone"
import type { OperatorHalonRegressionCase, OperatorHalonRegressionRun } from "@/types/serializers"

type CaseStatus = OperatorHalonRegressionCase["status"]

export const CASE_STATUS_LABELS: Record<CaseStatus, string> = {
  [OPERATOR_REGRESSION_CASE_STATUSES.PENDING]: "Replaying",
  [OPERATOR_REGRESSION_CASE_STATUSES.PASSED]: "Passed",
  [OPERATOR_REGRESSION_CASE_STATUSES.FAILED]: "Failed",
  [OPERATOR_REGRESSION_CASE_STATUSES.ERRORED]: "Could not finish",
  [OPERATOR_REGRESSION_CASE_STATUSES.SKIPPED]: "Opted out",
}

const CASE_STATUS_TONES: Record<CaseStatus, Tone> = {
  [OPERATOR_REGRESSION_CASE_STATUSES.PENDING]: "active",
  [OPERATOR_REGRESSION_CASE_STATUSES.PASSED]: "success",
  [OPERATOR_REGRESSION_CASE_STATUSES.FAILED]: "error",
  [OPERATOR_REGRESSION_CASE_STATUSES.ERRORED]: "warning",
  [OPERATOR_REGRESSION_CASE_STATUSES.SKIPPED]: "neutral",
}

export function startedBy(run: OperatorHalonRegressionRun): string {
  return run.trigger === OPERATOR_REGRESSION_TRIGGERS.PROMPT_CHANGE ? "New prompt deployed" : `Run by ${run.startedBy ?? "an operator"}`
}

export function modelName(run: OperatorHalonRegressionRun): string {
  return run.model ?? "Halon's model"
}

export function RegressionStatus({ status }: { status: CaseStatus }) {
  return <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs whitespace-nowrap ${TONE_CLASSES[CASE_STATUS_TONES[status]]}`}>{CASE_STATUS_LABELS[status]}</span>
}
