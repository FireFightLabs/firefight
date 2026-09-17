const TODAY = { hour: "2-digit", minute: "2-digit" } as const
const OLDER = { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" } as const

export function clockTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, TODAY)
}

// A chat started this morning says the time, one from last week says the date too.
export function startedAt(iso: string): string {
  const when = new Date(iso)
  const now = new Date()
  const sameDay = when.toDateString() === now.toDateString()

  return sameDay ? `today at ${clockTime(iso)}` : when.toLocaleString(undefined, OLDER)
}
