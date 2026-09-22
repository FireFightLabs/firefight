import { useEffect, useRef, useState } from "react"
import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import type { AgentStep } from "@/pages/agent/types"

// A tool usually answers within a few dozen milliseconds, so a step's running and done events land in
// the same frame and the spinner never paints. Each step is shown running for at least this long, and
// steps that finish together settle one after another, so a person sees the work happen in order.
const SHOW_RUNNING_FOR_MS = 450
const SETTLE_APART_MS = 220

interface Shown {
  since: number
  settleAt: number | null
}

export function useSettledSteps(steps: AgentStep[]): AgentStep[] {
  const shown = useRef<Map<string, Shown>>(new Map())
  const lastSettle = useRef(0)
  const [ now, setNow ] = useState(() => Date.now())

  useEffect(() => {
    const clock = Date.now()
    for (const step of steps) {
      const entry = shown.current.get(step.key) ?? { since: clock, settleAt: null }
      if (step.status !== AGENT_STEP_STATUSES.RUNNING && entry.settleAt === null) {
        entry.settleAt = Math.max(entry.since + SHOW_RUNNING_FOR_MS, lastSettle.current + SETTLE_APART_MS, clock)
        lastSettle.current = entry.settleAt
      }
      shown.current.set(step.key, entry)
    }
    for (const key of shown.current.keys()) {
      if (!steps.some((step) => step.key === key)) {
        shown.current.delete(key)
      }
    }
    const pending = [ ...shown.current.values() ].map((entry) => entry.settleAt).filter((at): at is number => at !== null && at > clock)
    if (pending.length === 0) {
      return
    }
    const timer = setTimeout(() => setNow(Date.now()), Math.min(...pending) - clock)
    return () => clearTimeout(timer)
  }, [ steps, now ])

  return steps.map((step) => {
    const entry = shown.current.get(step.key)
    const stillSettling = entry?.settleAt !== null && entry?.settleAt !== undefined && entry.settleAt > now
    return stillSettling ? { ...step, status: AGENT_STEP_STATUSES.RUNNING } : step
  })
}
