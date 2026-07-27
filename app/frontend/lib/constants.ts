import type { CSSProperties } from "react"

export const LIFECYCLE_STAGES = {
  TRIAGE: "triage",
  ACTIVE: "active",
  CLOSED: "closed",
  CANCELED: "canceled",
} as const

export type LifecycleStageKey = (typeof LIFECYCLE_STAGES)[keyof typeof LIFECYCLE_STAGES]

const DEFAULT_SEVERITY_COLOR = "#3B82F6"

// The badge wears the colour the admin picked for the severity. It used to key
// off rank magnitude, which broke the moment rank became derived from ordering
// and ignored the chosen colour anyway.
export function severityBadgeStyle(color?: string | null): CSSProperties {
  const background = /^#[0-9a-f]{6}$/i.test(color ?? "") ? color! : DEFAULT_SEVERITY_COLOR
  return { backgroundColor: background, color: readableTextColor(background), borderColor: "transparent" }
}

// Relative luminance per WCAG, so a pale severity colour still reads.
function readableTextColor(hex: string) {
  const channel = (offset: number) => {
    const value = parseInt(hex.slice(offset, offset + 2), 16) / 255
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  }
  const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
  return luminance > 0.45 ? "#0B1220" : "#FFFFFF"
}

export function statusVariant(lifecycleStage: string) {
  switch (lifecycleStage) {
    case LIFECYCLE_STAGES.ACTIVE:
      return "default" as const
    case LIFECYCLE_STAGES.CLOSED:
      return "secondary" as const
    default:
      return "outline" as const
  }
}
