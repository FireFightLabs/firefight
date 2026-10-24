import { timeAgo } from "@/lib/time"

interface LiveUpdatesState {
  on: boolean
  lastEventAt: string | null
  checkedEvery: string | null
}

// "On, checked every 5 minutes, last event 3 minutes ago", said under a connection's Live updates heading. How often
// the change log is read is said only where the provider is sent changes another way as well.
export function liveUpdatesStatus(state: LiveUpdatesState): string {
  if (!state.on) {
    return "Off"
  }
  const checked = state.checkedEvery ? [`checked ${state.checkedEvery}`] : []
  const last = state.lastEventAt ? `last event ${timeAgo(state.lastEventAt)}` : "no change received yet"
  return ["On", ...checked, last].join(", ")
}

// "Live updates: on, last event 3 minutes ago", the same words on the map, where no heading names them.
export function liveUpdatesLine(state: LiveUpdatesState): string {
  const status = liveUpdatesStatus(state)
  return `Live updates: ${status.charAt(0).toLowerCase()}${status.slice(1)}`
}
