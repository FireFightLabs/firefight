import {
  IconBan,
  IconCircleCheck,
  IconCircleX,
  IconClock,
  IconLoader2,
  IconPlayerSkipForward,
  type Icon,
} from "@tabler/icons-react"

import type { RemediationStepStatus } from "@/lib/generated/constants"

// Where a step got to, by colour and by mark, so neither carries it alone. A proposed step says nothing yet.
const STEP_STATUS_STYLES: Record<RemediationStepStatus, { tone: string; icon: Icon | null }> = {
  proposed: { tone: "text-fg-secondary", icon: null },
  running: { tone: "text-stage-active", icon: IconLoader2 },
  waiting_approval: { tone: "text-warning", icon: IconClock },
  done: { tone: "text-success", icon: IconCircleCheck },
  failed: { tone: "text-error", icon: IconCircleX },
  declined: { tone: "text-error", icon: IconBan },
  skipped: { tone: "text-fg-muted", icon: IconPlayerSkipForward },
}

export function FixStepStatus({ status, label }: { status: RemediationStepStatus; label: string }) {
  const style = STEP_STATUS_STYLES[status]
  const StatusIcon = style.icon
  const spinning = StatusIcon === IconLoader2 ? "motion-safe:animate-spin" : ""

  return (
    <span className={`inline-flex items-center gap-1.5 text-xs font-medium ${style.tone}`}>
      {StatusIcon && <StatusIcon className={`size-3.5 shrink-0 ${spinning}`} />}
      {label}
    </span>
  )
}
