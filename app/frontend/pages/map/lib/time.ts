const MINUTE = 60
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

// "4 minutes ago", "3 hours ago", "2 days ago", for when a sweep ran or a change was seen.
export function timeAgo(iso: string, now: Date = new Date()): string {
  const seconds = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 1000))
  if (seconds < MINUTE) {
    return "just now"
  }
  if (seconds < HOUR) {
    return plural(Math.floor(seconds / MINUTE), "minute")
  }
  if (seconds < DAY) {
    return plural(Math.floor(seconds / HOUR), "hour")
  }
  return plural(Math.floor(seconds / DAY), "day")
}

// "12m", "3h", "2d", where a column of times needs to stay narrow.
export function shortAgo(iso: string, now: Date = new Date()): string {
  const seconds = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 1000))
  if (seconds < HOUR) {
    return `${Math.max(1, Math.floor(seconds / MINUTE))}m`
  }
  if (seconds < DAY) {
    return `${Math.floor(seconds / HOUR)}h`
  }
  return `${Math.floor(seconds / DAY)}d`
}

function plural(count: number, unit: string): string {
  return `${count} ${unit}${count === 1 ? "" : "s"} ago`
}
