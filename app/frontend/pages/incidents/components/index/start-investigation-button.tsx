import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import { IconListSearch, IconLoader2 } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { OPEN_INVESTIGATION_PROP } from "@/lib/generated/constants"
import { incidentInvestigationsPath } from "@/lib/routes"
import type { InvestigationStart } from "@/pages/incidents/types"

const SHARED = "h-8 gap-2 px-3 text-[12px]"

// Starts Halon on this incident, as Slack's Investigate button does. The run then opens over the page. When it cannot
// start the button stays and says why, and points at the run already working. Focusable while it cannot act, so the
// reason reaches a keyboard too.
export function StartInvestigationButton({ incidentId, start }: { incidentId: string; start: InvestigationStart }) {
  const [starting, setStarting] = useState(false)

  function finish() {
    setStarting(false)
  }

  function begin() {
    setStarting(true)
    router.post(incidentInvestigationsPath(incidentId), {}, { preserveScroll: true, onFinish: finish })
  }

  if (start.blockedReason) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          <Button variant="outline" size="sm" className={`${SHARED} cursor-default text-fg-disabled`} aria-disabled aria-label="Investigate">
            <IconListSearch className="size-3.5" />
            <span className="hidden sm:inline">Investigate</span>
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom" className="flex max-w-64 flex-col items-start gap-1">
          <span>{start.blockedReason}</span>
          {start.runningHref && (
            <Link
              href={start.runningHref}
              only={[OPEN_INVESTIGATION_PROP]}
              preserveScroll
              preserveState
              className="font-medium underline underline-offset-2"
            >
              Open the run
            </Link>
          )}
        </TooltipContent>
      </Tooltip>
    )
  }

  return (
    <Button variant="outline" size="sm" className={SHARED} disabled={starting} onClick={begin} aria-label="Investigate">
      {starting ? <IconLoader2 className="size-3.5 motion-safe:animate-spin" /> : <IconListSearch className="size-3.5" />}
      <span className="hidden sm:inline">Investigate</span>
    </Button>
  )
}
