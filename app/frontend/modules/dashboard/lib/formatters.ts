export function formatDuration(declaredAt: string, resolvedAt: string | null): string {
  const start = new Date(declaredAt)
  const end = resolvedAt ? new Date(resolvedAt) : new Date()
  const minutes = Math.floor((end.getTime() - start.getTime()) / 60000)

  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  const remainingMinutes = minutes % 60
  if (hours < 24) return `${hours}h ${remainingMinutes}m`
  const days = Math.floor(hours / 24)
  return `${days}d ${hours % 24}h`
}

export function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}
