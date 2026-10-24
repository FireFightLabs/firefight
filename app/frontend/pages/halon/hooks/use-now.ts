import { useEffect, useState } from "react"

const TICK_MS = 1_000

// The time now, moving each second while ticking, so how long a step has gone and when a watch reads next count on
// their own between the run's reloads.
export function useNow(ticking: boolean): number {
  const [ now, setNow ] = useState(() => Date.now())

  useEffect(() => {
    if (!ticking) {
      return
    }
    const timer = window.setInterval(() => setNow(Date.now()), TICK_MS)
    return () => window.clearInterval(timer)
  }, [ ticking ])

  return now
}
