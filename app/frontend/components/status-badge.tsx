import type { StatusCompact } from "@/types/serializers"
import { StatusIcon } from "@/components/status-icon"

// Tinted from the status's own colour, so a custom colour reads the same way the defaults do.
function tintedStyle(color: string) {
  return {
    backgroundColor: `color-mix(in srgb, ${color} 15%, var(--surface-card))`,
    borderColor: `color-mix(in srgb, ${color} 35%, var(--surface-card))`,
    color,
  }
}

export function StatusBadge({ status }: { status: StatusCompact }) {
  return (
    <span
      data-slot="status-badge"
      className="inline-flex min-w-30 shrink-0 items-center justify-center gap-1.5 rounded-md border px-2.5 py-[3px] text-[12px] leading-4 font-medium whitespace-nowrap"
      style={tintedStyle(status.color)}
    >
      <StatusIcon statusSlug={status.slug} lifecycleStage={status.lifecycleStage} />
      <span className="truncate">{status.name}</span>
    </span>
  )
}
