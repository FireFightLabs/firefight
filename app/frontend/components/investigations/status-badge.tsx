import { IconAlertTriangle, IconBan, IconCircleCheck, IconClock, IconLoader2, type Icon } from "@tabler/icons-react"

import type { InvestigationStatus } from "@/lib/generated/constants"
import { STATUS_LABELS, isKeyOf, labelFor } from "@/components/investigations/labels"
import { STATUS_TONES, TONE_CLASSES } from "@/components/investigations/tone"

// Each state carries its own mark, so the badge reads without its colour.
const STATUS_ICONS: Record<InvestigationStatus, Icon> = {
  pending: IconClock,
  running: IconLoader2,
  succeeded: IconCircleCheck,
  failed: IconAlertTriangle,
  canceled: IconBan,
}

export function InvestigationStatusBadge({ status }: { status: string }) {
  const known = isKeyOf(STATUS_TONES, status)
  const tone = known ? STATUS_TONES[status] : "neutral"
  const StatusIcon = known ? STATUS_ICONS[status] : IconClock
  const spinning = StatusIcon === IconLoader2 ? "motion-safe:animate-spin" : ""

  return (
    <span className={`inline-flex w-fit items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium tracking-wide transition-colors duration-150 ${TONE_CLASSES[tone]}`}>
      <StatusIcon className={`size-3.5 ${spinning}`} strokeWidth={1.75} />
      {labelFor(STATUS_LABELS, status)}
    </span>
  )
}
