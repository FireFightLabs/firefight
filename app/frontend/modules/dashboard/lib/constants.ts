export const SEVERITY_OPTIONS = ["Critical", "High", "Medium", "Low"] as const

export const STATUS_OPTIONS = ["active", "closed"] as const

export const STATUS_LABELS: Record<string, string> = {
  active: "Active",
  closed: "Closed",
}

export function severityVariant(rank: number) {
  if (rank >= 4) return "destructive" as const
  if (rank >= 3) return "default" as const
  return "secondary" as const
}

export function statusVariant(lifecycleStage: string) {
  switch (lifecycleStage) {
    case "active":
      return "default" as const
    case "closed":
      return "secondary" as const
    default:
      return "outline" as const
  }
}
