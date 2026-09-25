const MICROS_PER_DOLLAR = 1_000_000

// Spend is kept in millionths of a dollar. Operators read dollars, with cents below a dollar kept.
export function dollars(micros: number | null | undefined): string {
  if (micros === null || micros === undefined) {
    return "-"
  }
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(micros / MICROS_PER_DOLLAR)
}

export function seconds(total: number | null | undefined): string {
  if (total === null || total === undefined) {
    return "-"
  }
  const minutes = Math.floor(total / 60)
  return minutes > 0 ? `${minutes}m ${String(total % 60).padStart(2, "0")}s` : `${total}s`
}

export function milliseconds(total: number | null | undefined): string {
  if (total === null || total === undefined) {
    return "-"
  }
  return total >= 1000 ? `${(total / 1000).toFixed(1)} s` : `${total} ms`
}

export function percent(part: number, whole: number): string {
  return whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-"
}

export function count(value: number): string {
  return new Intl.NumberFormat("en-US", { notation: value >= 10_000 ? "compact" : "standard" }).format(value)
}

// How long ago, in the largest unit that fits.
export function since(at: string | null | undefined, now: Date = new Date()): string {
  if (!at) {
    return "-"
  }
  const total = Math.max(0, Math.round((now.getTime() - new Date(at).getTime()) / 1000))
  if (total < 60) {
    return `${total}s`
  }
  if (total < 3600) {
    return `${Math.floor(total / 60)} min`
  }
  if (total < 86_400) {
    return `${Math.floor(total / 3600)} h`
  }
  return `${Math.floor(total / 86_400)} d`
}
