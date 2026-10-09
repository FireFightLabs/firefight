import type { ReactNode } from "react"

import { TONE_CLASSES } from "@/pages/operator/lib/tone"

export function Chip({ children }: { children: ReactNode }) {
  return <span className={`rounded-full border px-2.5 py-1 font-mono ${TONE_CLASSES.neutral}`}>{children}</span>
}
