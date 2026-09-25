import type { ReactNode } from "react"

import { TONE_CLASSES } from "@/pages/operator/lib/tone"

type StatTone = "neutral" | "rose" | "amber"

// One figure with what it counts and one line of context under it. A figure that needs a person is coloured.
export function Stat({ label, value, note, tone = "neutral" }: { label: string; value: ReactNode; note?: ReactNode; tone?: StatTone }) {
  const coloured = tone !== "neutral"
  return (
    <div className={`flex min-w-0 flex-col gap-1 rounded-lg border px-4 py-3 ${coloured ? TONE_CLASSES[tone] : "border-border bg-card"}`}>
      <span className={`text-[11px] font-medium tracking-[0.12em] uppercase ${coloured ? "" : "text-muted-foreground"}`}>{label}</span>
      <span className="font-mono text-2xl font-semibold tracking-tight text-foreground tabular-nums">{value}</span>
      {note && <span className="text-muted-foreground truncate text-xs">{note}</span>}
    </div>
  )
}
