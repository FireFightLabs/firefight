import type { ToolActivity } from "@/lib/agent-chat/types"

// The words under a running step: what the tool said, or how far it got when it said only a count.
export function activityWords(activity: ToolActivity): string {
  if (activity.message) {
    return activity.message
  }
  if (activity.value !== null && activity.total !== null) {
    return `${activity.value} of ${activity.total}`
  }

  return "Working"
}

// How much of a counted piece of work is done, from 0 to 1, or null when the tool did not count it.
export function activityShare(activity: ToolActivity): number | null {
  if (activity.value === null || activity.total === null || activity.total <= 0) {
    return null
  }

  return Math.min(1, Math.max(0, activity.value / activity.total))
}
