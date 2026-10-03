import type { CSSProperties } from "react"

const ON_DARK_TEXT = "var(--text-headline)"
const ON_LIGHT_TEXT = "var(--on-sev)"
const FALLBACK_SEVERITY_COLOR = "var(--sev-minor)"
// Mirror --bg and --text-headline in styles/theme.css, since the contrast maths needs real values.
const PAGE_BACKGROUND = "#121312"
const HEADLINE_TEXT = "#f9f8f5"

// The badge wears the colour the admin picked, not one keyed off rank, which
// comes from ordering and has no fixed scale.
export function severityBadgeStyle(color?: string | null): CSSProperties {
  if (!color || !/^#[0-9a-f]{6}$/i.test(color)) {
    return { backgroundColor: FALLBACK_SEVERITY_COLOR, color: ON_LIGHT_TEXT, borderColor: "transparent" }
  }
  return { backgroundColor: color, color: readableTextColor(color), borderColor: "transparent" }
}

// Dark text wherever it out-contrasts the light one, so a pale or mid colour never carries white.
function readableTextColor(hex: string) {
  const fill = luminance(hex)
  const darkContrast = (fill + 0.05) / (luminance(PAGE_BACKGROUND) + 0.05)
  const lightContrast = (luminance(HEADLINE_TEXT) + 0.05) / (fill + 0.05)
  return darkContrast >= lightContrast ? ON_LIGHT_TEXT : ON_DARK_TEXT
}

// Relative luminance per WCAG.
function luminance(hex: string) {
  const channel = (offset: number) => {
    const value = parseInt(hex.slice(offset, offset + 2), 16) / 255
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
}
