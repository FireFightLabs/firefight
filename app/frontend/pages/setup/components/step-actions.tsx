import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { Blocked } from "@/pages/settings/components/blocked-tooltip"

// The foot of a step: whatever else it offers, then the button that moves setup on. A blocked button says why.
export function StepActions({
  label = "Continue",
  blockedReason,
  busy = false,
  onContinue,
  children,
}: {
  label?: string
  blockedReason?: string | null
  busy?: boolean
  onContinue: () => void
  children?: ReactNode
}) {
  return (
    <div className="flex flex-col-reverse gap-3 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-end">
      {children}
      <Blocked reason={blockedReason ?? undefined} side="top">
        <Button onClick={onContinue} disabled={Boolean(blockedReason) || busy} className="w-full sm:w-auto">
          {label}
        </Button>
      </Blocked>
    </div>
  )
}
