import { useEffect, useState } from "react"

const TICK_MS = 1_000

// Seconds since startedAt, counting on its own while running, and the time it took once it ended.
export function useElapsed(startedAt: string, finishedAt: string | null, running: boolean): number {
  const [ now, setNow ] = useState(() => Date.now())

  useEffect(() => {
    if (!running) {
      return
    }
    const timer = window.setInterval(() => setNow(Date.now()), TICK_MS)
    return () => window.clearInterval(timer)
  }, [ running ])

  const end = finishedAt ? Date.parse(finishedAt) : now
  return Math.max(0, Math.round((end - Date.parse(startedAt)) / 1000))
}
