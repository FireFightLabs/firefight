import { CHAT_MEMORY_STATES } from "@/lib/generated/constants"
import { STATE_LABELS, STATE_TONES } from "@/lib/memory-labels"

export function MemoryNote({ state, text }: { state: string; text: string }) {
  const known = CHAT_MEMORY_STATES.find((each) => each === state)

  return (
    <div className="flex flex-col items-start gap-1.5 rounded-lg border border-border bg-background/50 px-3 py-2">
      {known && <span className={`rounded-full border px-2 py-0.5 text-[11px] font-medium ${STATE_TONES[known]}`}>{STATE_LABELS[known]}</span>}
      <p className="text-sm">{text}</p>
    </div>
  )
}
