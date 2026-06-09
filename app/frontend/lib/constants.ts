export const LIFECYCLE_STAGES = {
  TRIAGE: "triage",
  ACTIVE: "active",
  CLOSED: "closed",
  CANCELED: "canceled",
} as const

export type LifecycleStageKey = (typeof LIFECYCLE_STAGES)[keyof typeof LIFECYCLE_STAGES]

export function severityBadgeClass(rank: number) {
  if (rank >= 4) return "bg-[#D42B2B] text-white border-transparent"
  if (rank >= 3) return "bg-[#E07A12] text-white border-transparent"
  return "bg-[#3B82F6] text-white border-transparent"
}

export function statusVariant(lifecycleStage: string) {
  switch (lifecycleStage) {
    case LIFECYCLE_STAGES.ACTIVE:
      return "default" as const
    case LIFECYCLE_STAGES.CLOSED:
      return "secondary" as const
    default:
      return "outline" as const
  }
}
