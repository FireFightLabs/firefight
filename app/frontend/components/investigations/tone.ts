import type { HypothesisStatus, InvestigationStatus, InvestigationStepStatus } from "@/lib/generated/constants"

// One palette for the page, so a supported theory, a finished run and an answer read as the same lime.
// Working is the cyan the app uses for an active incident, an open theory the violet of triage.
export type Tone = "brand" | "active" | "success" | "warning" | "error" | "open" | "neutral"

export const TONE_CLASSES: Record<Tone, string> = {
  brand: "border-brand-border bg-brand-tint text-brand",
  active: "border-stage-active-border bg-stage-active-tint text-stage-active",
  success: "border-success-border bg-success-tint text-success",
  warning: "border-warning-border bg-warning-tint text-warning",
  error: "border-error-border bg-error-tint text-error",
  open: "border-stage-triage-border bg-stage-triage-tint text-stage-triage",
  neutral: "border-border-strong bg-surface-card text-fg-secondary",
}

export const STATUS_TONES: Record<InvestigationStatus, Tone> = {
  pending: "neutral",
  running: "active",
  succeeded: "success",
  failed: "warning",
  canceled: "neutral",
}

export const HYPOTHESIS_TONES: Record<HypothesisStatus, Tone> = {
  open: "open",
  supported: "success",
  refuted: "error",
}

export const STEP_TONES: Record<InvestigationStepStatus, Tone> = {
  pending: "neutral",
  running: "active",
  succeeded: "neutral",
  failed: "error",
}
