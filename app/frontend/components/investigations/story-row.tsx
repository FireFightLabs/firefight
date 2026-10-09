import type { ReactNode } from "react"

import { formatTime } from "@/lib/formatters"
import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"

interface StoryRowProps {
  id?: string
  marker: ReactNode
  tone: Tone
  title: ReactNode
  at?: string | null
  aside?: ReactNode
  connected: boolean
  children?: ReactNode
}

// One entry on the run's story, its marker on the line that joins them, and what it says under it.
export function StoryRow({ id, marker, tone, title, at, aside, connected, children }: StoryRowProps) {
  return (
    <li id={id} className="relative scroll-mt-6 pb-5 target:[&_.story-card]:border-brand">
      {connected && <div aria-hidden className="absolute top-7 bottom-0 left-[14px] w-px bg-border" />}
      <div className="flex items-center gap-4">
        <div className={`relative z-10 flex size-[28px] shrink-0 items-center justify-center rounded-full border ${TONE_CLASSES[tone]}`}>
          {marker}
        </div>
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 text-sm">{title}</div>
        <span className="flex shrink-0 items-center gap-2 text-xs tabular-nums text-fg-muted">
          {aside}
          {at && <span>{formatTime(at)}</span>}
        </span>
      </div>
      {children && <div className="story-card mt-2.5 ml-[44px] rounded-lg border border-border bg-surface-card px-3.5 py-2.5 transition-colors duration-200">{children}</div>}
    </li>
  )
}
