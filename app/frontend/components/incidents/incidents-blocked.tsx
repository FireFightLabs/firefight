import type { ReactNode } from "react"
import { usePage } from "@inertiajs/react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import type { SharedProps } from "@/types"

// Why this workspace cannot declare an incident yet, from the server. Every Declare button reads it.
export function useIncidentsBlockedReason(): string | undefined {
  const { currentWorkspace } = usePage<SharedProps>().props
  return currentWorkspace?.incidentsBlockedReason
}

// A disabled button swallows pointer events, so the tooltip rides on a span. Children render bare with no reason.
export function IncidentsBlocked({ reason, children }: { reason?: string; children: ReactNode }) {
  if (!reason) {
    return children
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-block" tabIndex={0}>{children}</span>
      </TooltipTrigger>
      <TooltipContent side="bottom" className="max-w-56">{reason}</TooltipContent>
    </Tooltip>
  )
}
