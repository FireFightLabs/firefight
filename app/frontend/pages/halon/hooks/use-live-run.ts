import { usePoll } from "@inertiajs/react"
import { useEffect } from "react"

import { WORKFLOW_RUN_OPEN_STATUSES } from "@/lib/generated/constants"

const REFRESH_EVERY_MS = 3000
const OPEN: readonly string[] = WORKFLOW_RUN_OPEN_STATUSES

// A run still going reloads itself every few seconds, and stops once it ended.
export function useLiveRun(status: string) {
  const live = OPEN.includes(status)
  const { start, stop } = usePoll(REFRESH_EVERY_MS, { only: [ "run" ] }, { autoStart: false })

  useEffect(() => {
    if (!live) {
      return
    }
    start()
    return stop
  }, [live, start, stop])
}
