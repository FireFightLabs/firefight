import { IconLoader2 } from "@tabler/icons-react"

import { STATUS_LABELS, isKeyOf, labelFor } from "@/components/investigations/labels"
import { STATUS_TONES, TONE_CLASSES } from "@/components/investigations/tone"
import { isLive } from "@/components/investigations/use-live-investigation"

export function InvestigationStatusBadge({ status }: { status: string }) {
  const tone = isKeyOf(STATUS_TONES, status) ? STATUS_TONES[status] : "neutral"

  return (
    <span className={`inline-flex w-fit items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-medium tracking-wide ${TONE_CLASSES[tone]}`}>
      {isLive(status) ? <IconLoader2 className="size-3 animate-spin" /> : <span className="size-1.5 rounded-full bg-current" />}
      {labelFor(STATUS_LABELS, status)}
    </span>
  )
}
