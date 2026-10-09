import { OPERATOR_PROCESS_TONES } from "@/pages/operator/generated/constants"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorTraceSpan } from "@/types/serializers"

type SpanTone = OperatorTraceSpan["tone"]

const TONE_MEANINGS: { tone: SpanTone; meaning: string }[] = [
  { tone: OPERATOR_PROCESS_TONES.INFO, meaning: "Model call or a step in its thinking" },
  { tone: OPERATOR_PROCESS_TONES.OK, meaning: "Went fine" },
  { tone: OPERATOR_PROCESS_TONES.BAD, meaning: "Failed or denied" },
  { tone: OPERATOR_PROCESS_TONES.WARN, meaning: "Worth a look, such as a limit reached or a call Firefight's own rule refused" },
  { tone: OPERATOR_PROCESS_TONES.IDLE, meaning: "Skipped or ruled out" },
]

// Explains what the bar and diamond shapes and each colour mean.
export function TraceLegend() {
  return (
    <div className="text-muted-foreground flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-border px-2 pb-4 text-xs">
      <span className="flex items-center gap-2">
        <span className="border-muted-foreground/70 h-3 w-6 rounded-sm border" />
        Took time, from when it started for as long as it ran
      </span>
      <span className="flex items-center gap-2">
        <span className="border-muted-foreground/70 size-2.5 rotate-45 rounded-[2px] border" />
        A moment
      </span>
      {TONE_MEANINGS.map((entry) => (
        <span key={entry.tone} className="flex items-center gap-2">
          <span className={`size-2.5 rounded-full border bg-current! ${processToneClasses(entry.tone)}`} />
          {entry.meaning}
        </span>
      ))}
    </div>
  )
}
