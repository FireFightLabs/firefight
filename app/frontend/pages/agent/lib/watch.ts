// How long a watch has gone, as its card's header says it: seconds within the first minute, then minutes, then hours.
export function watchDuration(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}s`
  }
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) {
    return `${minutes} min`
  }
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  return rest > 0 ? `${hours} hr ${rest} min` : `${hours} hr`
}
