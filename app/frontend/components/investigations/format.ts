// How long a run or a step took, from seconds, in the largest two units.
export function formatSeconds(seconds: number | null | undefined): string {
  if (seconds == null) {
    return "-"
  }
  if (seconds < 60) {
    return `${seconds}s`
  }
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) {
    return `${minutes}m ${seconds % 60}s`
  }
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}
