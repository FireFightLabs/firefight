import type { SeverityCompact } from "@/types/serializers"
import { severityBadgeStyle } from "@/lib/severity-color"
import { SeverityBars } from "@/components/severity-bars"

export function SeverityBadge({ severity }: { severity: SeverityCompact }) {
  return (
    <span
      data-slot="severity-badge"
      className="inline-flex w-28 shrink-0 items-center justify-center gap-1.5 rounded-md px-2.5 py-1 text-[12px] leading-4 font-medium whitespace-nowrap"
      style={severityBadgeStyle(severity.color)}
    >
      <SeverityBars filled={severity.signalBars} />
      <span className="truncate">{severity.name}</span>
    </span>
  )
}
