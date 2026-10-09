export function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

export function formatDateTime(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}

export function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
}

export function formatDuration(start: string, end: string | null | undefined): string {
  const startTime = new Date(start)
  const endTime = end ? new Date(end) : new Date()
  const minutes = Math.floor((endTime.getTime() - startTime.getTime()) / 60000)

  if (minutes < 60) {
    return `${minutes}m`
  }
  const hours = Math.floor(minutes / 60)
  const remainingMinutes = minutes % 60
  if (hours < 24) {
    return remainingMinutes > 0 ? `${hours}h ${remainingMinutes}m` : `${hours}h`
  }
  const days = Math.floor(hours / 24)
  const remainingHours = hours % 24
  return remainingHours > 0 ? `${days}d ${remainingHours}h` : `${days}d`
}

// "a", "a or b", "a, b or c".
export function orList(words: string[]): string {
  if (words.length <= 1) {
    return words.join("")
  }
  return `${words.slice(0, -1).join(", ")} or ${words[words.length - 1]}`
}

// "a", "a and b", "a, b and c".
export function andList(words: string[]): string {
  if (words.length <= 1) {
    return words.join("")
  }
  return `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}`
}

// "a minute", "30 minutes", "an hour", "2 hours", for a length of time the server set in minutes.
export function minutesInWords(minutes: number): string {
  if (minutes % 60 === 0) {
    const hours = minutes / 60
    return hours === 1 ? "an hour" : `${hours} hours`
  }
  return minutes === 1 ? "a minute" : `${minutes} minutes`
}

// A share of a whole as a whole percentage, or a dash when there is nothing to divide by.
export function percent(part: number, whole: number): string {
  return whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-"
}
