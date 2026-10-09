import { type Icon, IconAlertTriangle, IconCheck, IconEye, IconHourglass, IconPlayerStop, IconProgress, IconX } from "@tabler/icons-react"

import { formatTime } from "@/lib/formatters"
import { WATCH_TONES } from "@/lib/generated/constants"
import type { AgentChatWatchUpdate } from "@/types/serializers"

const TONE_ICONS: Record<AgentChatWatchUpdate["tone"], { icon: Icon; className: string }> = {
  [WATCH_TONES.STARTED]: { icon: IconEye, className: "text-ink-2" },
  [WATCH_TONES.MILESTONE]: { icon: IconCheck, className: "text-success" },
  [WATCH_TONES.PART_FAILED]: { icon: IconX, className: "text-danger" },
  [WATCH_TONES.HANDED_BACK]: { icon: IconAlertTriangle, className: "text-warning" },
  [WATCH_TONES.SLOW]: { icon: IconHourglass, className: "text-warning" },
  [WATCH_TONES.PROGRESS]: { icon: IconProgress, className: "text-ink-2" },
  [WATCH_TONES.DONE]: { icon: IconCheck, className: "text-success" },
  [WATCH_TONES.FAILED]: { icon: IconX, className: "text-danger" },
  [WATCH_TONES.TIMED_OUT]: { icon: IconAlertTriangle, className: "text-warning" },
  [WATCH_TONES.STOPPED]: { icon: IconPlayerStop, className: "text-ink-3" },
}

// One line a watch said after Halon's answer, placed where it happened among the chat's messages.
export function WatchUpdate({ update }: { update: AgentChatWatchUpdate }) {
  const mark = TONE_ICONS[update.tone]
  const Mark = mark.icon
  return (
    <div className="flex max-w-160 items-start gap-2" aria-label="Watch update">
      <Mark className={`mt-1 size-4 shrink-0 ${mark.className}`} />
      <div className="flex min-w-0 flex-col gap-0.5">
        <p className="text-[14px] leading-relaxed text-ink [overflow-wrap:anywhere]">{update.text}</p>
        <span className="text-[12px] text-ink-3">Watching {update.title} · {formatTime(update.at)}</span>
      </div>
    </div>
  )
}
