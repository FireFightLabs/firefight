import { type Icon, IconCheck, IconCircleDashed, IconLoader2, IconMinus, IconX } from "@tabler/icons-react"

import { WATCH_STEP_STATUSES } from "@/lib/generated/constants"
import type { AgentChatWatch } from "@/types/serializers"

type WatchStepStatus = AgentChatWatch["steps"][number]["status"]

const STEP_ICONS: Record<WatchStepStatus, { icon: Icon; className: string }> = {
  [WATCH_STEP_STATUSES.WAITING]: { icon: IconCircleDashed, className: "text-ink-3" },
  [WATCH_STEP_STATUSES.RUNNING]: { icon: IconLoader2, className: "text-ink-2 motion-safe:animate-spin" },
  [WATCH_STEP_STATUSES.SUCCEEDED]: { icon: IconCheck, className: "text-success" },
  [WATCH_STEP_STATUSES.FAILED]: { icon: IconX, className: "text-danger" },
  [WATCH_STEP_STATUSES.UNFOLLOWABLE]: { icon: IconMinus, className: "text-ink-3" },
}

interface WatchStepProps {
  label: string
  status: WatchStepStatus
  state: string | null
}

export function WatchStep({ label, status, state }: WatchStepProps) {
  const mark = STEP_ICONS[status]
  const Mark = mark.icon
  return (
    <li className="flex items-start gap-2 text-[13px] leading-relaxed">
      <Mark className={`mt-1 size-3.5 shrink-0 ${mark.className}`} />
      <span className="min-w-0 [overflow-wrap:anywhere]">
        <span className="font-medium text-ink">{label}</span>
        {state && <span className="text-ink-2">. {state}</span>}
      </span>
    </li>
  )
}
