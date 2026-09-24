import type { HypothesisStatus, InvestigationStatus, InvestigationStepStatus } from "@/lib/generated/constants"

// One palette for the page, so a supported theory, a finished step and an answer read as the same green.
export type Tone = "primary" | "emerald" | "amber" | "rose" | "violet" | "neutral"

export const TONE_CLASSES: Record<Tone, string> = {
  primary: "border-primary/50 bg-primary/10 text-primary",
  emerald: "border-emerald-500/50 bg-emerald-500/10 text-emerald-600 dark:border-emerald-400/50 dark:bg-emerald-400/10 dark:text-emerald-400",
  amber: "border-amber-500/50 bg-amber-500/10 text-amber-600 dark:border-amber-400/50 dark:bg-amber-400/10 dark:text-amber-400",
  rose: "border-rose-500/50 bg-rose-500/10 text-rose-600 dark:border-rose-400/50 dark:bg-rose-400/10 dark:text-rose-400",
  violet: "border-violet-500/50 bg-violet-500/10 text-violet-600 dark:border-violet-400/50 dark:bg-violet-400/10 dark:text-violet-400",
  neutral: "border-border bg-card text-muted-foreground",
}

export const STATUS_TONES: Record<InvestigationStatus, Tone> = {
  pending: "neutral",
  running: "primary",
  succeeded: "emerald",
  failed: "amber",
  canceled: "neutral",
}

export const HYPOTHESIS_TONES: Record<HypothesisStatus, Tone> = {
  open: "violet",
  supported: "emerald",
  refuted: "rose",
}

export const STEP_TONES: Record<InvestigationStepStatus, Tone> = {
  pending: "neutral",
  running: "primary",
  succeeded: "neutral",
  failed: "rose",
}
