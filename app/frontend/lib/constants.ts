export const LIFECYCLE_STAGES = {
  TRIAGE: "triage",
  ACTIVE: "active",
  CLOSED: "closed",
} as const

export type LifecycleStageKey = (typeof LIFECYCLE_STAGES)[keyof typeof LIFECYCLE_STAGES]

export function severityBadgeClass(rank: number) {
  if (rank >= 4) return "bg-red-950 text-red-400 border-red-800/50"
  if (rank >= 3) return "bg-amber-950 text-amber-400 border-amber-800/50"
  return "bg-slate-800/60 text-slate-300 border-slate-600/50"
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
