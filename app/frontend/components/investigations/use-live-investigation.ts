import { usePoll } from "@inertiajs/react"
import { useEffect } from "react"

import { INVESTIGATION_LIVE_STATUSES } from "@/lib/generated/constants"

const REFRESH_EVERY_MS = 3000
const LIVE_STATUSES: readonly string[] = INVESTIGATION_LIVE_STATUSES

export function isLive(status: string): boolean {
  return LIVE_STATUSES.includes(status)
}

// A run that is still working reloads the one prop that holds it every few seconds, and stops once it has an
// answer or has stopped. The page names the prop, since a run is drawn over whatever page it belongs to.
export function useLiveInvestigation(status: string | undefined, prop: string): boolean {
  const live = status != null && isLive(status)
  const { start, stop } = usePoll(REFRESH_EVERY_MS, { only: [prop] }, { autoStart: false })

  useEffect(() => {
    if (!live) {
      return
    }
    start()
    return stop
  }, [live, start, stop])

  return live
}
