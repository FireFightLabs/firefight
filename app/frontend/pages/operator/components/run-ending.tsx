import { OPERATOR_HALON_ENDINGS } from "@/lib/generated/constants"
import { TONE_CLASSES, type Tone } from "@/pages/operator/lib/tone"
import type { OperatorHalonRun } from "@/types/serializers"

type Ending = OperatorHalonRun["ending"]

export const ENDING_LABELS: Record<Ending, string> = {
  [OPERATOR_HALON_ENDINGS.ANSWERED]: "Answered",
  [OPERATOR_HALON_ENDINGS.STOPPED]: "Stopped",
  [OPERATOR_HALON_ENDINGS.FAILED]: "Failed",
  [OPERATOR_HALON_ENDINGS.LIVE]: "Working",
}

export const ENDING_TONES: Record<Ending, Tone> = {
  [OPERATOR_HALON_ENDINGS.ANSWERED]: "success",
  [OPERATOR_HALON_ENDINGS.STOPPED]: "warning",
  [OPERATOR_HALON_ENDINGS.FAILED]: "error",
  [OPERATOR_HALON_ENDINGS.LIVE]: "active",
}

export function RunEnding({ ending }: { ending: Ending }) {
  return <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${TONE_CLASSES[ENDING_TONES[ending]]}`}>{ENDING_LABELS[ending]}</span>
}
