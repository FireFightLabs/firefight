import { timeAgo } from "@/lib/time"

interface LiveUpdatesState {
  on: boolean
  lastEventAt: string | null
}

// "Live updates: on, last event 3 minutes ago", the same words on the map and on the connection.
export function liveUpdatesLine(state: LiveUpdatesState): string {
  if (!state.on) {
    return "Live updates: off"
  }
  if (!state.lastEventAt) {
    return "Live updates: on, no change received yet"
  }
  return `Live updates: on, last event ${timeAgo(state.lastEventAt)}`
}
