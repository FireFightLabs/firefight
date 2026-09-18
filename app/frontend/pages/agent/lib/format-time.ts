const CLOCK = { hour: "2-digit", minute: "2-digit" } as const

export function clockTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, CLOCK)
}
