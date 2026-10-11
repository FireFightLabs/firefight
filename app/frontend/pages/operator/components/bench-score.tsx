import { OPERATOR_BENCH_SCENARIO_STATUSES, OPERATOR_BENCH_TRIGGERS } from "@/pages/operator/generated/constants"
import { TONE_CLASSES, type Tone } from "@/pages/operator/lib/tone"
import type { OperatorHalonBenchRun, OperatorHalonBenchScenario } from "@/types/serializers"

type ScenarioStatus = OperatorHalonBenchScenario["status"]
type Dimension = "right" | "movedForward" | "askedWhenNeeded" | "cost" | "cited"

// What a bench replay is scored on, in the order the page shows them. The first three make up quality, and cost and
// citing are apart. short is the column heading where a table has no room for the label.
export const DIMENSIONS: { key: Dimension; label: string; short: string; note: string }[] = [
  { key: "right", label: "Right", short: "Right", note: "the right answer, and nothing a right run never does" },
  { key: "movedForward", label: "Moved forward", short: "Forward", note: "proposed and took the next step unprompted" },
  { key: "askedWhenNeeded", label: "Asked when needed", short: "Asked", note: "confirmed changes only, asked nothing it could look up" },
  { key: "cost", label: "Cost", short: "Cost", note: "within the scenario's ceiling" },
  { key: "cited", label: "Cited", short: "Cited", note: "linked the evidence that shows its answer" },
]

export const QUALITY_NOTE = "right, moved forward and asked when needed"

// How far apart a scenario's repeats, or a run's passes, landed. Nothing to compare with fewer than two.
export function spreadText(spread: number | null | undefined): string {
  return spread === null || spread === undefined ? "one replay" : `spread ${spread.toFixed(2)}`
}

const STATUS_LABELS: Record<ScenarioStatus, string> = {
  [OPERATOR_BENCH_SCENARIO_STATUSES.PENDING]: "Replaying",
  [OPERATOR_BENCH_SCENARIO_STATUSES.SCORED]: "Scored",
  [OPERATOR_BENCH_SCENARIO_STATUSES.ERRORED]: "Could not finish",
}

const STATUS_TONES: Record<ScenarioStatus, Tone> = {
  [OPERATOR_BENCH_SCENARIO_STATUSES.PENDING]: "active",
  [OPERATOR_BENCH_SCENARIO_STATUSES.SCORED]: "neutral",
  [OPERATOR_BENCH_SCENARIO_STATUSES.ERRORED]: "warning",
}

// Scores run from 0 to 1, shown to two places.
export function score(value: number | null | undefined): string {
  return value === null || value === undefined ? "-" : value.toFixed(2)
}

export function benchStartedBy(run: OperatorHalonBenchRun): string {
  if (run.trigger === OPERATOR_BENCH_TRIGGERS.CI) {
    return run.label ? `CI, ${run.label}` : "CI"
  }
  if (run.trigger === OPERATOR_BENCH_TRIGGERS.TERMINAL) {
    return run.label ? `Terminal, ${run.label}` : "Terminal"
  }
  return `Run by ${run.startedBy ?? "an operator"}`
}

export function ScoreChange({ change, tolerance }: { change: number | null | undefined; tolerance: number }) {
  if (change === null || change === undefined) {
    return <span className="text-muted-foreground">-</span>
  }
  const tone = change < -tolerance ? "text-error" : change > tolerance ? "text-success" : "text-muted-foreground"
  return <span className={`font-mono tabular-nums ${tone}`}>{`${change > 0 ? "+" : ""}${change.toFixed(2)}`}</span>
}

export function BenchScenarioStatus({ status }: { status: ScenarioStatus }) {
  return <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs whitespace-nowrap ${TONE_CLASSES[STATUS_TONES[status]]}`}>{STATUS_LABELS[status]}</span>
}
