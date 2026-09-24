import { usePoll } from "@inertiajs/react"
import { useEffect } from "react"

import { INVESTIGATION_LIVE_STATUSES, INVESTIGATION_PROPS } from "@/lib/generated/constants"

const REFRESH_EVERY_MS = 3000
const LIVE_STATUSES: readonly string[] = INVESTIGATION_LIVE_STATUSES

// A run that is still working reloads its own record every few seconds, and stops once it has an answer or has stopped.
export function useLiveInvestigation(status: string): boolean {
  const live = LIVE_STATUSES.includes(status)
  const { start, stop } = usePoll(REFRESH_EVERY_MS, { only: [INVESTIGATION_PROPS.INVESTIGATION] }, { autoStart: false })

  useEffect(() => {
    if (!live) {
      return
    }
    start()
    return stop
  }, [live, start, stop])

  return live
}
