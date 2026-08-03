import type { ReactNode } from "react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

// A disabled control swallows pointer events, so the tooltip rides on a span.
// Renders children bare when there is no reason, so callers can pass a
// *_blocked_reason straight through.
export function Blocked({
  reason,
  side = "left",
  children,
}: {
  reason?: string
  side?: "top" | "right" | "bottom" | "left"
  children: ReactNode
}) {
  if (!reason) {
    return children
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-block">{children}</span>
      </TooltipTrigger>
      <TooltipContent side={side} className="max-w-56">{reason}</TooltipContent>
    </Tooltip>
  )
}
