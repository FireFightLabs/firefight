import { useEffect, useState } from "react"

const TICK_MS = 15_000
const MINUTE_MS = 60_000

// How long an approved call has left to be run, said the way a person reads it, such as "Expires in 52 minutes". It
// counts down on its own, and says "Expired" once the time has passed, before the server's own word arrives.
export function useExpiresIn(expiresAt: string | null | undefined): { label: string | null; expired: boolean } {
  const [ now, setNow ] = useState(() => Date.now())

  useEffect(() => {
    if (!expiresAt) {
      return
    }
    const timer = window.setInterval(() => setNow(Date.now()), TICK_MS)
    return () => window.clearInterval(timer)
  }, [ expiresAt ])

  if (!expiresAt) {
    return { label: null, expired: false }
  }

  const left = Date.parse(expiresAt) - now
  if (left <= 0) {
    return { label: "Expired", expired: true }
  }

  const minutes = Math.ceil(left / MINUTE_MS)
  if (left < MINUTE_MS) {
    return { label: "Expires in less than a minute", expired: false }
  }
  return { label: `Expires in ${minutes} ${minutes === 1 ? "minute" : "minutes"}`, expired: false }
}
